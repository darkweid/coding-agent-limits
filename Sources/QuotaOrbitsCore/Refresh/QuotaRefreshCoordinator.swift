import Combine
import Foundation

@MainActor
public final class QuotaRefreshCoordinator: ObservableObject {
    @Published public private(set) var snapshot = QuotaSnapshot.initial
    public private(set) var isRefreshing = false

    private let claudeGate: SourceFetchGate<[ClaudeAccountQuota]>
    private let codexGate: SourceFetchGate<CodexQuota>
    private let ticker: any RefreshTicking
    private let now: @Sendable () -> Date
    private let refreshInterval: Duration
    private let timeout: Duration
    private let timeoutScheduler: any RefreshTimeoutScheduling
    private var tickerTask: Task<Void, Never>?
    private var isAwaitingInitialTick = false
    private var nextIdleWaiterID = 0
    private var idleWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    public convenience init(
        claude: any ClaudeQuotaFetching,
        codex: any CodexQuotaFetching,
        ticker: any RefreshTicking = MinuteTicker(),
        now: @escaping @Sendable () -> Date = { Date() },
        refreshInterval: Duration = .seconds(60),
        timeout: Duration = .seconds(10)
    ) {
        self.init(
            claude: claude,
            codex: codex,
            ticker: ticker,
            now: now,
            refreshInterval: refreshInterval,
            timeout: timeout,
            timeoutScheduler: ContinuousRefreshTimeoutScheduler()
        )
    }

    @_spi(Testing)
    public init(
        claude: any ClaudeQuotaFetching,
        codex: any CodexQuotaFetching,
        ticker: any RefreshTicking,
        now: @escaping @Sendable () -> Date,
        refreshInterval: Duration = .seconds(60),
        timeout: Duration = .seconds(10),
        timeoutScheduler: any RefreshTimeoutScheduling
    ) {
        self.claudeGate = SourceFetchGate(
            source: .claude,
            operation: { try await claude.fetch() }
        )
        self.codexGate = SourceFetchGate(
            source: .codex,
            operation: { try await codex.fetch() }
        )
        self.ticker = ticker
        self.now = now
        self.refreshInterval = refreshInterval
        self.timeout = timeout
        self.timeoutScheduler = timeoutScheduler
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
        resumeIdleWaitersIfNeeded()
    }

    public func refreshNow() async {
        guard !isRefreshing else { return }
        isAwaitingInitialTick = false
        isRefreshing = true
        snapshot.lastCycleStartedAt = now()
        SafeLogger.cycleStarted()
        defer {
            isRefreshing = false
            resumeIdleWaitersIfNeeded()
        }

        await withTaskGroup(of: CompletedFetch.self) { group in
            let claudeGate = self.claudeGate
            let codexGate = self.codexGate
            let timeout = self.timeout
            let timeoutScheduler = self.timeoutScheduler

            group.addTask {
                .claude(
                    await claudeGate.fetch(
                        timeout: timeout,
                        timeoutScheduler: timeoutScheduler
                    )
                )
            }
            group.addTask {
                .codex(
                    await codexGate.fetch(
                        timeout: timeout,
                        timeoutScheduler: timeoutScheduler
                    )
                )
            }

            for await completed in group {
                guard !Task.isCancelled else { continue }
                switch completed {
                case let .claude(result): applyClaude(result)
                case let .codex(result): applyCodex(result)
                }
            }
        }
    }

    @_spi(Testing)
    public func waitForIdleForTesting() async {
        await waitUntilIdle()
    }

    public func waitUntilIdle() async {
        guard !isIdle, !Task.isCancelled else { return }
        nextIdleWaiterID += 1
        let waiterID = nextIdleWaiterID

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isIdle || Task.isCancelled {
                    continuation.resume()
                } else {
                    idleWaiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelIdleWaiter(waiterID)
            }
        }
    }

    @_spi(Testing)
    public var idleWaiterCountForTesting: Int {
        idleWaiters.count
    }

    private var isIdle: Bool {
        !isAwaitingInitialTick && !isRefreshing
    }

    private func resumeIdleWaitersIfNeeded() {
        guard isIdle else { return }
        let waiters = Array(idleWaiters.values)
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func cancelIdleWaiter(_ waiterID: Int) {
        idleWaiters.removeValue(forKey: waiterID)?.resume()
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
}

private struct FetchFailure: Error, Sendable {
    let message: String
    let category: FailureCategory
}

private enum CompletedFetch: Sendable {
    case claude(Result<[ClaudeAccountQuota], FetchFailure>)
    case codex(Result<CodexQuota, FetchFailure>)
}

private actor SourceFetchGate<Value: Sendable> {
    private struct InFlight {
        let id: Int
        let task: Task<Result<Value, FetchFailure>, Never>
    }

    private struct Waiter {
        let id: Int
        let continuation: CheckedContinuation<Result<Value, FetchFailure>, Never>
        let timeoutTask: Task<Void, Never>
    }

    private let source: SourceKind
    private let operation: @Sendable () async throws -> Value
    private var nextID = 0
    private var inFlight: InFlight?
    private var waiter: Waiter?

    init(
        source: SourceKind,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        self.source = source
        self.operation = operation
    }

    func fetch(
        timeout: Duration,
        timeoutScheduler: any RefreshTimeoutScheduling
    ) async -> Result<Value, FetchFailure> {
        guard !Task.isCancelled else {
            return .failure(timeoutFailure())
        }
        guard inFlight == nil else {
            return .failure(timeoutFailure())
        }

        nextID += 1
        let id = nextID
        let operation = self.operation
        let task = Task.detached { () -> Result<Value, FetchFailure> in
            do {
                return .success(try await operation())
            } catch {
                return .failure(sanitizeFetchError(error))
            }
        }
        inFlight = InFlight(id: id, task: task)

        Task { [weak self] in
            let result = await task.value
            await self?.fetchFinished(id: id, result: result)
        }

        let timeoutSource = source
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do {
                        try await timeoutScheduler.wait(
                            for: timeout,
                            source: timeoutSource
                        )
                    } catch {
                        return
                    }
                    await self?.deadlineReached(id: id)
                }
                waiter = Waiter(
                    id: id,
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
            }
        } onCancel: {
            Task { await self.callerCancelled(id: id) }
        }
    }

    private func fetchFinished(
        id: Int,
        result: Result<Value, FetchFailure>
    ) {
        guard inFlight?.id == id else { return }
        inFlight = nil
        guard let waiter, waiter.id == id else { return }
        self.waiter = nil
        waiter.timeoutTask.cancel()
        waiter.continuation.resume(returning: result)
    }

    private func deadlineReached(id: Int) {
        guard let waiter, waiter.id == id else { return }
        self.waiter = nil
        if inFlight?.id == id {
            inFlight?.task.cancel()
        }
        waiter.continuation.resume(returning: .failure(timeoutFailure()))
    }

    private func callerCancelled(id: Int) {
        guard let waiter, waiter.id == id else { return }
        self.waiter = nil
        waiter.timeoutTask.cancel()
        if inFlight?.id == id {
            inFlight?.task.cancel()
        }
        waiter.continuation.resume(returning: .failure(timeoutFailure()))
    }

    private func timeoutFailure() -> FetchFailure {
        FetchFailure(message: "Quota request timed out.", category: .timeout)
    }
}

private func sanitizeFetchError(_ error: Error) -> FetchFailure {
    if let error = error as? ClaudeQuotaError {
        switch error {
        case .commandFailed:
            return FetchFailure(
                message: "Quota command failed.",
                category: .exitCode
            )
        case .invalidResponse, .expectedTwoAccounts:
            return invalidResponseFailure()
        }
    }
    if error is CodexQuotaError {
        return invalidResponseFailure()
    }
    if let error = error as? CommandRunnerError {
        switch error {
        case .launchFailed:
            return FetchFailure(
                message: "Quota command could not be launched.",
                category: .launch
            )
        case .timedOut:
            return timeoutFetchFailure()
        }
    }
    if let error = error as? CodexAppServerError {
        switch error {
        case .protocolError:
            return invalidResponseFailure()
        case .timedOut:
            return timeoutFetchFailure()
        case .transportClosed:
            return transportFetchFailure()
        }
    }
    if let error = error as? JSONLineTransportError {
        switch error {
        case .failedToStart:
            return FetchFailure(
                message: "Quota service could not be launched.",
                category: .launch
            )
        case .lineTooLong:
            return invalidResponseFailure()
        case .transportClosed:
            return transportFetchFailure()
        }
    }
    return FetchFailure(
        message: "Quota data is unavailable.",
        category: .transport
    )
}

private func timeoutFetchFailure() -> FetchFailure {
    FetchFailure(message: "Quota request timed out.", category: .timeout)
}

private func invalidResponseFailure() -> FetchFailure {
    FetchFailure(
        message: "Quota response was invalid.",
        category: .invalidResponse
    )
}

private func transportFetchFailure() -> FetchFailure {
    FetchFailure(
        message: "Quota connection closed.",
        category: .transport
    )
}
