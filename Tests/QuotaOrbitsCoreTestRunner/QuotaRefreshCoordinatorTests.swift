import Foundation
@_spi(Testing) import QuotaOrbitsCore

enum QuotaRefreshCoordinatorTests {
    static let cases: [TestCase] = [
        TestCase(name: "QuotaRefreshCoordinatorTests.testStartRefreshesBothSourcesImmediately") {
            try await testStartRefreshesBothSourcesImmediately()
        },
        TestCase(name: "QuotaRefreshCoordinatorTests.testOneFailureDoesNotReplaceOtherSuccess") {
            try await testOneFailureDoesNotReplaceOtherSuccess()
        },
        TestCase(name: "QuotaRefreshCoordinatorTests.testFailureAfterSuccessKeepsStaleValue") {
            try await testFailureAfterSuccessKeepsStaleValue()
        },
        TestCase(name: "QuotaRefreshCoordinatorTests.testOverlappingRefreshIsIgnored") {
            try await testOverlappingRefreshIsIgnored()
        },
        TestCase(name: "QuotaRefreshCoordinatorTests.testManualRefreshRunsWithoutStartingTicker") {
            try await testManualRefreshRunsWithoutStartingTicker()
        },
        TestCase(name: "QuotaRefreshCoordinatorTests.testCompletedSourceIsAppliedBeforeOtherSourceFinishes") {
            try await testCompletedSourceIsAppliedBeforeOtherSourceFinishes()
        },
        TestCase(name: "QuotaRefreshCoordinatorTests.testManualTickerDrivesDeterministicSubsequentCycle") {
            try await testManualTickerDrivesDeterministicSubsequentCycle()
        },
        TestCase(name: "QuotaRefreshCoordinatorTests.testUnknownErrorDetailsAreNotExposed") {
            try await testUnknownErrorDetailsAreNotExposed()
        },
        TestCase(name: "QuotaRefreshCoordinatorTests.testDeadlineDoesNotJoinNonCancellableFetch") {
            try await testDeadlineDoesNotJoinNonCancellableFetch()
        }
    ]

    @MainActor
    private static func testStartRefreshesBothSourcesImmediately() async throws {
        let ticker = ManualRefreshTicker()
        let coordinator = makeCoordinator(
            claude: SequencedClaudeSource([.success(twoClaudeAccounts)]),
            codex: SequencedCodexSource([.success(codexQuota)]),
            ticker: ticker
        )

        coordinator.start()
        await coordinator.waitForIdleForTesting()
        coordinator.stop()
        ticker.finish()

        try TestSupport.assertEqual(
            coordinator.snapshot.claude,
            .available(twoClaudeAccounts, updatedAt: fixedNow)
        )
        try TestSupport.assertEqual(
            coordinator.snapshot.codex,
            .available(codexQuota, updatedAt: fixedNow)
        )
        try TestSupport.assertEqual(coordinator.snapshot.lastCycleStartedAt, fixedNow)
    }

    @MainActor
    private static func testOneFailureDoesNotReplaceOtherSuccess() async throws {
        let coordinator = makeCoordinator(
            claude: SequencedClaudeSource([.failure(.fixture("cswap unavailable"))]),
            codex: SequencedCodexSource([.success(codexQuota)])
        )

        await coordinator.refreshNow()

        try TestSupport.assertEqual(
            coordinator.snapshot.claude,
            .unavailable(message: "Quota data is unavailable.")
        )
        try TestSupport.assertEqual(
            coordinator.snapshot.codex,
            .available(codexQuota, updatedAt: fixedNow)
        )
    }

    @MainActor
    private static func testFailureAfterSuccessKeepsStaleValue() async throws {
        let claude = SequencedClaudeSource([
            .success(twoClaudeAccounts),
            .failure(.fixture("timeout"))
        ])
        let coordinator = makeCoordinator(
            claude: claude,
            codex: SequencedCodexSource([.success(codexQuota), .success(codexQuota)])
        )

        await coordinator.refreshNow()
        await coordinator.refreshNow()

        try TestSupport.assertEqual(
            coordinator.snapshot.claude,
            .stale(
                twoClaudeAccounts,
                lastSuccessAt: fixedNow,
                message: "Quota data is unavailable."
            )
        )
        try TestSupport.assertEqual(
            coordinator.snapshot.codex,
            .available(codexQuota, updatedAt: fixedNow)
        )
    }

    @MainActor
    private static func testOverlappingRefreshIsIgnored() async throws {
        let blocked = BlockingClaudeSource(value: twoClaudeAccounts)
        let coordinator = makeCoordinator(
            claude: blocked,
            codex: SequencedCodexSource([.success(codexQuota)])
        )

        async let first: Void = coordinator.refreshNow()
        await blocked.waitUntilFetchStarted()
        await coordinator.refreshNow()

        try TestSupport.assertEqual(await blocked.fetchCount, 1)
        await blocked.release()
        await first
    }

    @MainActor
    private static func testManualRefreshRunsWithoutStartingTicker() async throws {
        let claude = SequencedClaudeSource([.success(twoClaudeAccounts)])
        let codex = SequencedCodexSource([.success(codexQuota)])
        let coordinator = makeCoordinator(claude: claude, codex: codex)

        await coordinator.refreshNow()

        try TestSupport.assertEqual(await claude.fetchCount, 1)
        try TestSupport.assertEqual(await codex.fetchCount, 1)
        try TestSupport.assertEqual(coordinator.isRefreshing, false)
    }

    @MainActor
    private static func testCompletedSourceIsAppliedBeforeOtherSourceFinishes() async throws {
        let blocked = BlockingClaudeSource(value: twoClaudeAccounts)
        let codex = SequencedCodexSource([.success(codexQuota)])
        let coordinator = makeCoordinator(claude: blocked, codex: codex)

        async let cycle: Void = coordinator.refreshNow()
        await blocked.waitUntilFetchStarted()
        await codex.waitUntilFetchCount(1)
        try await waitUntil {
            coordinator.snapshot.codex == .available(codexQuota, updatedAt: fixedNow)
        }

        try TestSupport.assertEqual(coordinator.snapshot.claude, .loading)
        await blocked.release()
        await cycle
    }

    @MainActor
    private static func testManualTickerDrivesDeterministicSubsequentCycle() async throws {
        let ticker = ManualRefreshTicker()
        let claude = SequencedClaudeSource([
            .success(twoClaudeAccounts),
            .failure(.fixture("second cycle failed"))
        ])
        let codex = SequencedCodexSource([.success(codexQuota), .success(codexQuota)])
        let coordinator = makeCoordinator(claude: claude, codex: codex, ticker: ticker)

        coordinator.start()
        await coordinator.waitForIdleForTesting()
        ticker.yield()
        await claude.waitUntilFetchCount(2)
        await coordinator.waitForIdleForTesting()
        coordinator.stop()
        ticker.finish()

        try TestSupport.assertEqual(await claude.fetchCount, 2)
        try TestSupport.assertEqual(
            coordinator.snapshot.claude,
            .stale(
                twoClaudeAccounts,
                lastSuccessAt: fixedNow,
                message: "Quota data is unavailable."
            )
        )
    }

    @MainActor
    private static func testUnknownErrorDetailsAreNotExposed() async throws {
        let coordinator = makeCoordinator(
            claude: UnknownFailureClaudeSource(),
            codex: SequencedCodexSource([.success(codexQuota)])
        )

        await coordinator.refreshNow()

        try TestSupport.assertEqual(
            coordinator.snapshot.claude,
            .unavailable(message: "Quota data is unavailable.")
        )
        try TestSupport.assertFalse(String(describing: coordinator.snapshot).contains("secret"))
    }

    @MainActor
    private static func testDeadlineDoesNotJoinNonCancellableFetch() async throws {
        let blocked = NonCancellableClaudeSource()
        let secondCodexQuota = CodexQuota(
            weekly: QuotaWindow(usedPercent: 10, resetsAt: reset),
            creditsBalance: Decimal(string: "20.00")
        )
        let codex = SequencedCodexSource([
            .success(codexQuota),
            .success(secondCodexQuota)
        ])
        let timeoutScheduler = ManualRefreshTimeoutScheduler()
        let coordinator = QuotaRefreshCoordinator(
            claude: blocked,
            codex: codex,
            ticker: ManualRefreshTicker(),
            now: { fixedNow },
            timeout: .seconds(10),
            timeoutScheduler: timeoutScheduler
        )
        let firstCycle = Task {
            await coordinator.refreshNow()
        }

        await blocked.waitUntilFetchStarted()
        await timeoutScheduler.waitUntilScheduled(for: .claude)
        await timeoutScheduler.fire(.claude)
        await firstCycle.value

        try TestSupport.assertEqual(coordinator.isRefreshing, false)

        await coordinator.refreshNow()

        try TestSupport.assertEqual(coordinator.isRefreshing, false)
        try TestSupport.assertEqual(await blocked.fetchCount, 1)
        try TestSupport.assertEqual(await codex.fetchCount, 2)
        try TestSupport.assertEqual(
            coordinator.snapshot.codex,
            .available(secondCodexQuota, updatedAt: fixedNow)
        )
    }

    @MainActor
    private static func makeCoordinator(
        claude: any ClaudeQuotaFetching,
        codex: any CodexQuotaFetching,
        ticker: any RefreshTicking = ManualRefreshTicker()
    ) -> QuotaRefreshCoordinator {
        QuotaRefreshCoordinator(
            claude: claude,
            codex: codex,
            ticker: ticker,
            now: { fixedNow },
            refreshInterval: .seconds(60),
            timeout: .seconds(1)
        )
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

    private static let fixedNow = Date(timeIntervalSince1970: 1_786_080_000)
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
        )
    ]
    private static let codexQuota = CodexQuota(
        weekly: QuotaWindow(usedPercent: 35, resetsAt: reset),
        creditsBalance: Decimal(string: "12.50")
    )
}

private struct UnknownFailureClaudeSource: ClaudeQuotaFetching {
    struct SecretError: Error, CustomStringConvertible {
        let description = "stderr token=secret raw-json={private:true}"
    }

    func fetch() async throws -> [ClaudeAccountQuota] {
        throw SecretError()
    }
}
