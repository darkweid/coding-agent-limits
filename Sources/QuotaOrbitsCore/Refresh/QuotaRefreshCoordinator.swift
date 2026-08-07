import Combine
import Foundation

@MainActor
public final class QuotaRefreshCoordinator: ObservableObject {
    @Published public private(set) var snapshot = QuotaSnapshot.initial
    public private(set) var isRefreshing = false

    private let claude: any ClaudeQuotaFetching
    private let codex: any CodexQuotaFetching
    private let ticker: any RefreshTicking
    private let now: @Sendable () -> Date
    private let refreshInterval: Duration
    private let timeout: Duration
    private var tickerTask: Task<Void, Never>?
    private var isAwaitingInitialTick = false

    public init(
        claude: any ClaudeQuotaFetching,
        codex: any CodexQuotaFetching,
        ticker: any RefreshTicking = MinuteTicker(),
        now: @escaping @Sendable () -> Date = { Date() },
        refreshInterval: Duration = .seconds(60),
        timeout: Duration = .seconds(10)
    ) {
        self.claude = claude
        self.codex = codex
        self.ticker = ticker
        self.now = now
        self.refreshInterval = refreshInterval
        self.timeout = timeout
    }

    public func start() {
        guard tickerTask == nil else { return }
        isAwaitingInitialTick = true
        let ticks = ticker.ticks(every: refreshInterval)
        tickerTask = Task { [weak self] in
            for await _ in ticks {
                guard !Task.isCancelled else { break }
                await self?.refreshNow()
            }
        }
    }

    public func stop() {
        tickerTask?.cancel()
        tickerTask = nil
        isAwaitingInitialTick = false
    }

    public func refreshNow() async {
        guard !isRefreshing else { return }
        isAwaitingInitialTick = false
        isRefreshing = true
        snapshot.lastCycleStartedAt = now()
        SafeLogger.cycleStarted()
        defer { isRefreshing = false }

        await withTaskGroup(of: CompletedFetch.self) { group in
            let claude = self.claude
            let codex = self.codex
            let timeout = self.timeout

            group.addTask {
                .claude(
                    await Self.fetch(
                        source: .claude,
                        timeout: timeout,
                        operation: { try await claude.fetch() }
                    )
                )
            }
            group.addTask {
                .codex(
                    await Self.fetch(
                        source: .codex,
                        timeout: timeout,
                        operation: { try await codex.fetch() }
                    )
                )
            }

            for await completed in group {
                switch completed {
                case let .claude(result): applyClaude(result)
                case let .codex(result): applyCodex(result)
                }
            }
        }
    }

    @_spi(Testing)
    public func waitForIdleForTesting() async {
        while isAwaitingInitialTick || isRefreshing {
            await Task.yield()
        }
    }

    private func applyClaude(
        _ result: Result<[ClaudeAccountQuota], FetchFailure>
    ) {
        switch result {
        case let .success(value):
            snapshot.claude = .available(value, updatedAt: now())
            SafeLogger.sourceSucceeded(.claude)
        case let .failure(failure):
            snapshot.claude = staleOrUnavailable(
                previous: snapshot.claude,
                failure: failure
            )
            SafeLogger.sourceFailed(.claude, category: failure.category)
        }
    }

    private func applyCodex(_ result: Result<CodexQuota, FetchFailure>) {
        switch result {
        case let .success(value):
            snapshot.codex = .available(value, updatedAt: now())
            SafeLogger.sourceSucceeded(.codex)
        case let .failure(failure):
            snapshot.codex = staleOrUnavailable(
                previous: snapshot.codex,
                failure: failure
            )
            SafeLogger.sourceFailed(.codex, category: failure.category)
        }
    }

    private func staleOrUnavailable<Value>(
        previous: SourceSnapshot<Value>,
        failure: FetchFailure
    ) -> SourceSnapshot<Value> where Value: Equatable & Sendable {
        switch previous {
        case let .available(value, updatedAt):
            return .stale(
                value,
                lastSuccessAt: updatedAt,
                message: failure.message
            )
        case let .stale(value, lastSuccessAt, _):
            return .stale(
                value,
                lastSuccessAt: lastSuccessAt,
                message: failure.message
            )
        case .loading, .unavailable:
            return .unavailable(message: failure.message)
        }
    }

    nonisolated private static func fetch<Value: Sendable>(
        source: SourceKind,
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async -> Result<Value, FetchFailure> {
        await withTaskGroup(of: FetchRace<Value>.self) { group in
            group.addTask {
                do {
                    return .completed(.success(try await operation()))
                } catch {
                    return .completed(.failure(sanitize(error, source: source)))
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }

            guard let first = await group.next() else {
                return .failure(defaultFailure(for: source))
            }
            group.cancelAll()
            switch first {
            case let .completed(result): return result
            case .timedOut:
                return .failure(
                    FetchFailure(message: "Request timed out.", category: .timeout)
                )
            case .cancelled:
                return .failure(defaultFailure(for: source))
            }
        }
    }

    nonisolated private static func sanitize(
        _ error: Error,
        source: SourceKind
    ) -> FetchFailure {
        guard let safeError = error as? any SafeQuotaFetchError,
              !safeError.safeMessage.isEmpty
        else {
            return defaultFailure(for: source)
        }
        return FetchFailure(
            message: safeError.safeMessage,
            category: safeError.failureCategory
        )
    }

    nonisolated private static func defaultFailure(
        for source: SourceKind
    ) -> FetchFailure {
        switch source {
        case .claude:
            return FetchFailure(
                message: "Claude quota unavailable.",
                category: .transport
            )
        case .codex:
            return FetchFailure(
                message: "Codex quota unavailable.",
                category: .transport
            )
        }
    }
}

private struct FetchFailure: Error, Sendable {
    let message: String
    let category: FailureCategory
}

private enum CompletedFetch: Sendable {
    case claude(Result<[ClaudeAccountQuota], FetchFailure>)
    case codex(Result<CodexQuota, FetchFailure>)
}

private enum FetchRace<Value: Sendable>: Sendable {
    case completed(Result<Value, FetchFailure>)
    case timedOut
    case cancelled
}

extension ClaudeQuotaError: SafeQuotaFetchError {
    public var safeMessage: String {
        switch self {
        case .commandFailed: return "Claude quota command failed."
        case .invalidResponse: return "Claude quota response was invalid."
        case .expectedTwoAccounts: return "Two Claude accounts are required."
        }
    }

    public var failureCategory: FailureCategory {
        switch self {
        case .commandFailed: return .exitCode
        case .invalidResponse, .expectedTwoAccounts: return .invalidResponse
        }
    }
}

extension CodexQuotaError: SafeQuotaFetchError {
    public var safeMessage: String { "Codex quota response was invalid." }
    public var failureCategory: FailureCategory { .invalidResponse }
}

extension CommandRunnerError: SafeQuotaFetchError {
    public var safeMessage: String {
        switch self {
        case .launchFailed: return "Quota command could not be launched."
        case .timedOut: return "Request timed out."
        }
    }

    public var failureCategory: FailureCategory {
        switch self {
        case .launchFailed: return .launch
        case .timedOut: return .timeout
        }
    }
}

extension CodexAppServerError: SafeQuotaFetchError {
    public var safeMessage: String {
        switch self {
        case .protocolError: return "Codex returned an invalid response."
        case .timedOut: return "Request timed out."
        case .transportClosed: return "Codex connection closed."
        }
    }

    public var failureCategory: FailureCategory {
        switch self {
        case .protocolError: return .invalidResponse
        case .timedOut: return .timeout
        case .transportClosed: return .transport
        }
    }
}

extension JSONLineTransportError: SafeQuotaFetchError {
    public var safeMessage: String {
        switch self {
        case .failedToStart: return "Codex could not be launched."
        case .lineTooLong: return "Codex returned an invalid response."
        case .transportClosed: return "Codex connection closed."
        }
    }

    public var failureCategory: FailureCategory {
        switch self {
        case .failedToStart: return .launch
        case .lineTooLong: return .invalidResponse
        case .transportClosed: return .transport
        }
    }
}
