import Combine
import Foundation

@MainActor
public final class QuotaFeedRefreshCoordinator: ObservableObject {
    @Published public private(set) var snapshot: QuotaFeedSnapshot
    public private(set) var isRefreshing = false

    private struct Slot {
        let sourceID: QuotaSourceID
        let providerID: ProviderID
        let gate: NeutralSourceFetchGate
    }

    private let slots: [Slot]
    private let ticker: any RefreshTicking
    private let now: @Sendable () -> Date
    private let timeout: Duration
    private let timeoutScheduler: any RefreshTimeoutScheduling
    private var refreshInterval: Duration
    private var scheduleTask: Task<Void, Never>?
    private var cycleTask: Task<Void, Never>?

    public convenience init(
        sources: [any QuotaSource],
        ticker: any RefreshTicking = IntervalTicker(),
        now: @escaping @Sendable () -> Date = Date.init,
        refreshInterval: Duration = .seconds(60),
        timeout: Duration = .seconds(10)
    ) {
        self.init(
            sources: sources,
            ticker: ticker,
            now: now,
            refreshInterval: refreshInterval,
            timeout: timeout,
            timeoutScheduler: ContinuousRefreshTimeoutScheduler()
        )
    }

    @_spi(Testing)
    public init(
        sources: [any QuotaSource],
        ticker: any RefreshTicking,
        now: @escaping @Sendable () -> Date,
        refreshInterval: Duration = .seconds(60),
        timeout: Duration = .seconds(10),
        timeoutScheduler: any RefreshTimeoutScheduling
    ) {
        slots = sources.map { source in
            Slot(
                sourceID: source.sourceID,
                providerID: source.providerID,
                gate: NeutralSourceFetchGate(
                    source: safeKind(for: source.providerID),
                    operation: { try await source.fetch() }
                )
            )
        }
        snapshot = QuotaFeedSnapshot(
            entries: sources.map {
                .init(sourceID: $0.sourceID, snapshot: .loading)
            }
        )
        self.ticker = ticker
        self.now = now
        self.refreshInterval = refreshInterval
        self.timeout = timeout
        self.timeoutScheduler = timeoutScheduler
    }

    public func start() {
        guard scheduleTask == nil else { return }
        requestCycle()
        installSchedule()
    }

    public func stop() async {
        scheduleTask?.cancel()
        scheduleTask = nil
        cycleTask?.cancel()
        await cycleTask?.value
        cycleTask = nil
    }

    public func updateRefreshInterval(_ interval: Duration) {
        refreshInterval = interval
        guard scheduleTask != nil else { return }
        scheduleTask?.cancel()
        scheduleTask = nil
        installSchedule()
    }

    public func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        snapshot.lastCycleStartedAt = now()
        SafeLogger.cycleStarted()
        defer { isRefreshing = false }

        await withTaskGroup(of: NeutralCompletedFetch.self) { group in
            for slot in slots {
                let timeout = self.timeout
                let scheduler = timeoutScheduler
                group.addTask {
                    NeutralCompletedFetch(
                        sourceID: slot.sourceID,
                        providerID: slot.providerID,
                        result: await slot.gate.fetch(
                            timeout: timeout,
                            timeoutScheduler: scheduler
                        )
                    )
                }
            }
            for await completed in group where !Task.isCancelled {
                apply(completed)
            }
        }
    }

    public func waitUntilIdle() async {
        while isRefreshing || cycleTask != nil {
            await Task.yield()
        }
    }

    private func requestCycle() {
        guard cycleTask == nil else { return }
        cycleTask = Task { [weak self] in
            guard let self else { return }
            await refreshNow()
            cycleTask = nil
        }
    }

    private func installSchedule() {
        let ticks = ticker.ticks(every: refreshInterval)
        scheduleTask = Task { [weak self] in
            for await _ in ticks {
                guard !Task.isCancelled else { break }
                self?.requestCycle()
            }
        }
    }

    private func apply(_ completed: NeutralCompletedFetch) {
        guard
            let index = snapshot.entries.firstIndex(where: {
                $0.sourceID == completed.sourceID
            })
        else { return }
        switch completed.result {
        case let .success(value):
            snapshot.entries[index].snapshot = .available(value, updatedAt: now())
            SafeLogger.sourceSucceeded(safeKind(for: completed.providerID))
        case let .failure(failure):
            snapshot.entries[index].snapshot = staleOrUnavailable(
                previous: snapshot.entries[index].snapshot,
                failure: failure
            )
            SafeLogger.sourceFailed(
                safeKind(for: completed.providerID),
                category: failure.category
            )
        }
    }

    private func staleOrUnavailable(
        previous: SourceSnapshot<ProviderQuota>,
        failure: NeutralFetchFailure
    ) -> SourceSnapshot<ProviderQuota> {
        switch previous {
        case let .available(value, updatedAt):
            return .stale(value, lastSuccessAt: updatedAt, message: failure.message)
        case let .stale(value, lastSuccessAt, _):
            return .stale(value, lastSuccessAt: lastSuccessAt, message: failure.message)
        case .loading, .unavailable:
            return .unavailable(message: failure.message)
        }
    }
}

private struct NeutralCompletedFetch: Sendable {
    let sourceID: QuotaSourceID
    let providerID: ProviderID
    let result: Result<ProviderQuota, NeutralFetchFailure>
}

private struct NeutralFetchFailure: Error, Sendable {
    let message: String
    let category: FailureCategory
}

private actor NeutralSourceFetchGate {
    private struct InFlight {
        let id: Int
        let task: Task<Result<ProviderQuota, NeutralFetchFailure>, Never>
    }

    private struct Waiter {
        let id: Int
        let continuation:
            CheckedContinuation<
                Result<ProviderQuota, NeutralFetchFailure>, Never
            >
        let timeoutTask: Task<Void, Never>
    }

    private let source: SourceKind
    private let operation: @Sendable () async throws -> ProviderQuota
    private var nextID = 0
    private var inFlight: InFlight?
    private var waiter: Waiter?

    init(
        source: SourceKind,
        operation: @escaping @Sendable () async throws -> ProviderQuota
    ) {
        self.source = source
        self.operation = operation
    }

    func fetch(
        timeout: Duration,
        timeoutScheduler: any RefreshTimeoutScheduling
    ) async -> Result<ProviderQuota, NeutralFetchFailure> {
        guard !Task.isCancelled, inFlight == nil else {
            return .failure(neutralTimeoutFailure())
        }
        nextID += 1
        let id = nextID
        let operation = self.operation
        let fetchTask = Task.detached { () -> Result<ProviderQuota, NeutralFetchFailure> in
            do {
                return .success(try await operation())
            } catch {
                return .failure(sanitizeNeutralFetchError(error))
            }
        }
        inFlight = InFlight(id: id, task: fetchTask)
        Task { [weak self] in
            let result = await fetchTask.value
            await self?.fetchFinished(id: id, result: result)
        }

        let timeoutSource = source
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do {
                        try await timeoutScheduler.wait(for: timeout, source: timeoutSource)
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
        result: Result<ProviderQuota, NeutralFetchFailure>
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
        if inFlight?.id == id { inFlight?.task.cancel() }
        waiter.continuation.resume(returning: .failure(neutralTimeoutFailure()))
    }

    private func callerCancelled(id: Int) {
        guard let waiter, waiter.id == id else { return }
        self.waiter = nil
        waiter.timeoutTask.cancel()
        if inFlight?.id == id { inFlight?.task.cancel() }
        waiter.continuation.resume(returning: .failure(neutralTimeoutFailure()))
    }
}

private func safeKind(for providerID: ProviderID) -> SourceKind {
    providerID == .codex ? .codex : .claude
}

private func sanitizeNeutralFetchError(_ error: Error) -> NeutralFetchFailure {
    if error is CswapQuotaError || error is ClaudeCodeQuotaError || error is CodexQuotaError {
        return NeutralFetchFailure(
            message: "Quota response was invalid.",
            category: .invalidResponse
        )
    }
    if let error = error as? CommandRunnerError, error == .timedOut {
        return neutralTimeoutFailure()
    }
    if let error = error as? ClaudeUsageTerminalError, error == .timedOut {
        return neutralTimeoutFailure()
    }
    return NeutralFetchFailure(
        message: "Quota data is unavailable.",
        category: .transport
    )
}

private func neutralTimeoutFailure() -> NeutralFetchFailure {
    NeutralFetchFailure(message: "Quota request timed out.", category: .timeout)
}
