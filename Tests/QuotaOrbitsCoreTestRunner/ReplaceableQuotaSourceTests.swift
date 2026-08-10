import Foundation
@_spi(Testing) import QuotaOrbitsCore

enum ReplaceableQuotaSourceTests {
    static let cases: [TestCase] = [
        TestCase(
            name:
                "ReplaceableQuotaSourceTests.testOutOfOrderCodexReplacementKeepsNewestTransportActive"
        ) {
            try await testOutOfOrderCodexReplacementKeepsNewestTransportActive()
        },
        TestCase(name: "QuotaRefreshCoordinatorTests.testIdleWaiterResumesAfterActiveCycle") {
            try await testIdleWaiterResumesAfterActiveCycle()
        },
        TestCase(
            name:
                "QuotaRefreshCoordinatorTests.testCancelledIdleWaiterIsRemovedBeforeCycleCompletes"
        ) {
            try await testCancelledIdleWaiterIsRemovedBeforeCycleCompletes()
        },
    ]

    private static func testOutOfOrderCodexReplacementKeepsNewestTransportActive() async throws {
        let initialTransport = ControllableStopTransport(blocksOnStop: true)
        let firstTransport = ControllableStopTransport()
        let newestTransport = ControllableStopTransport()
        let staleIncomingTransport = ControllableStopTransport()
        let slot = ReplaceableCodexQuotaSource(
            source: FixedCodexSource(marker: 10),
            transport: initialTransport
        )

        let firstReplacement = Task {
            await slot.replace(
                source: FixedCodexSource(marker: 20),
                transport: firstTransport,
                generation: 1
            )
        }
        await initialTransport.waitUntilStopStarted()

        try TestSupport.assertEqual(
            try await slot.fetch().weekly.remainingPercent,
            20
        )

        await slot.replace(
            source: FixedCodexSource(marker: 30),
            transport: newestTransport,
            generation: 2
        )
        await slot.replace(
            source: FixedCodexSource(marker: 5),
            transport: staleIncomingTransport,
            generation: 1
        )

        try TestSupport.assertEqual(
            try await slot.fetch().weekly.remainingPercent,
            30
        )
        try TestSupport.assertEqual(await newestTransport.stopCount, 0)
        try TestSupport.assertEqual(await staleIncomingTransport.stopCount, 1)

        await initialTransport.releaseStop()
        await firstReplacement.value

        try TestSupport.assertEqual(
            try await slot.fetch().weekly.remainingPercent,
            30
        )
        try TestSupport.assertEqual(await newestTransport.stopCount, 0)
    }

    @MainActor
    private static func testIdleWaiterResumesAfterActiveCycle() async throws {
        let claude = BlockingClaudeSource(value: twoClaudeAccounts)
        let coordinator = QuotaRefreshCoordinator(
            claude: claude,
            codex: StableCodexSource(value: codexQuota),
            ticker: ManualRefreshTicker()
        )
        let refresh = Task { await coordinator.refreshNow() }
        await claude.waitUntilFetchStarted()

        let waiter = Task {
            await coordinator.waitUntilIdle()
            return true
        }
        try await waitUntil { coordinator.idleWaiterCountForTesting == 1 }
        try TestSupport.assertEqual(coordinator.isRefreshing, true)

        await claude.release()
        try TestSupport.assertEqual(await waiter.value, true)
        await refresh.value
        try TestSupport.assertEqual(coordinator.idleWaiterCountForTesting, 0)
        try TestSupport.assertEqual(coordinator.isRefreshing, false)
    }

    @MainActor
    private static func testCancelledIdleWaiterIsRemovedBeforeCycleCompletes() async throws {
        let claude = BlockingClaudeSource(value: twoClaudeAccounts)
        let coordinator = QuotaRefreshCoordinator(
            claude: claude,
            codex: StableCodexSource(value: codexQuota),
            ticker: ManualRefreshTicker()
        )
        let refresh = Task { await coordinator.refreshNow() }
        await claude.waitUntilFetchStarted()

        let waiter = Task {
            await coordinator.waitUntilIdle()
            return Task.isCancelled
        }
        try await waitUntil { coordinator.idleWaiterCountForTesting == 1 }
        waiter.cancel()

        try TestSupport.assertEqual(await waiter.value, true)
        try TestSupport.assertEqual(coordinator.idleWaiterCountForTesting, 0)
        try TestSupport.assertEqual(coordinator.isRefreshing, true)

        await claude.release()
        await refresh.value
    }

    @MainActor
    private static func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async throws {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        throw AssertionFailure(message: "condition was not satisfied")
    }

    private static let reset = Date(timeIntervalSince1970: 1_786_166_400)
    private static let twoClaudeAccounts = [
        ClaudeAccountQuota(
            id: "1",
            alias: "max",
            isActive: true,
            fiveHour: QuotaWindow(usedPercent: 20, resetsAt: reset),
            weekly: QuotaWindow(usedPercent: 30, resetsAt: reset)
        ),
        ClaudeAccountQuota(
            id: "2",
            alias: "pro",
            isActive: false,
            fiveHour: QuotaWindow(usedPercent: 40, resetsAt: reset),
            weekly: QuotaWindow(usedPercent: 50, resetsAt: reset)
        ),
    ]
    private static let codexQuota = CodexQuota(
        weekly: QuotaWindow(usedPercent: 35, resetsAt: reset),
        creditsBalance: nil
    )
}

private actor FixedCodexSource: CodexQuotaFetching {
    private let marker: Double

    init(marker: Double) {
        self.marker = marker
    }

    func fetch() -> CodexQuota {
        CodexQuota(
            weekly: QuotaWindow(
                usedPercent: 100 - marker,
                resetsAt: Date(timeIntervalSince1970: 1_786_166_400)
            ),
            creditsBalance: nil
        )
    }
}

private actor ControllableStopTransport: JSONLineTransport {
    private let blocksOnStop: Bool
    private var stopStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var isStopReleased = false
    private(set) var stopCount = 0

    init(blocksOnStop: Bool = false) {
        self.blocksOnStop = blocksOnStop
    }

    func start() async throws {}
    func send(_ line: Data) async throws {}

    func nextLine() async throws -> Data {
        throw JSONLineTransportError.transportClosed
    }

    func stop() async {
        stopCount += 1
        let waiters = stopStartedWaiters
        stopStartedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard blocksOnStop, !isStopReleased else { return }
        await withCheckedContinuation { continuation in
            stopContinuation = continuation
        }
    }

    func waitUntilStopStarted() async {
        if stopCount > 0 { return }
        await withCheckedContinuation { continuation in
            stopStartedWaiters.append(continuation)
        }
    }

    func releaseStop() {
        isStopReleased = true
        stopContinuation?.resume()
        stopContinuation = nil
    }
}
