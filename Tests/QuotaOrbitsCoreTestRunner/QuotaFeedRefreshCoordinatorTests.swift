import Foundation
@_spi(Testing) import QuotaOrbitsCore

enum QuotaFeedRefreshCoordinatorTests {
    static let cases: [TestCase] = [
        TestCase(name: "QuotaFeedRefreshCoordinatorTests.testRefreshPreservesConfiguredSourceOrder")
        {
            let claude = SequencedQuotaSource(
                sourceID: .cswap,
                providerID: .claude,
                outcomes: [.success(quota(provider: .claude, accountID: "claude"))]
            )
            let codex = SequencedQuotaSource(
                sourceID: .codexAppServer,
                providerID: .codex,
                outcomes: [.success(quota(provider: .codex, accountID: "codex"))]
            )
            let coordinator = await QuotaFeedRefreshCoordinator(
                sources: [claude, codex],
                ticker: ManualRefreshTicker(),
                now: { Date(timeIntervalSince1970: 500) }
            )

            await coordinator.refreshNow()
            let snapshot = await coordinator.snapshot

            try TestSupport.assertEqual(
                snapshot.entries.map(\.sourceID), [.cswap, .codexAppServer])
            try TestSupport.assertEqual(
                snapshot.entries.compactMap { entry in
                    if case let .available(value, _) = entry.snapshot {
                        return value.accounts.first?.id
                    }
                    return nil
                },
                ["claude", "codex"]
            )
        },
        TestCase(name: "QuotaFeedRefreshCoordinatorTests.testFailureKeepsLastGoodValueStale") {
            let source = SequencedQuotaSource(
                sourceID: .cswap,
                providerID: .claude,
                outcomes: [
                    .success(quota(provider: .claude, accountID: "kept")),
                    .failure(.fixture("private details")),
                ]
            )
            let coordinator = await QuotaFeedRefreshCoordinator(
                sources: [source],
                ticker: ManualRefreshTicker(),
                now: { Date(timeIntervalSince1970: 700) }
            )

            await coordinator.refreshNow()
            await coordinator.refreshNow()
            let entry = await coordinator.snapshot.entries[0]

            guard case let .stale(value, lastSuccessAt, message) = entry.snapshot else {
                throw AssertionFailure(message: "expected stale snapshot")
            }
            try TestSupport.assertEqual(value.accounts[0].id, "kept")
            try TestSupport.assertEqual(lastSuccessAt, Date(timeIntervalSince1970: 700))
            try TestSupport.assertEqual(message, "Quota data is unavailable.")
            try TestSupport.assertFalse(message.contains("private"))
        },
        TestCase(name: "QuotaFeedRefreshCoordinatorTests.testTimeoutDoesNotJoinSourceCleanup") {
            let source = ReleasableQuotaSource()
            let scheduler = ManualRefreshTimeoutScheduler()
            let coordinator = await QuotaFeedRefreshCoordinator(
                sources: [source],
                ticker: ManualRefreshTicker(),
                now: { Date(timeIntervalSince1970: 900) },
                timeout: .seconds(10),
                timeoutScheduler: scheduler
            )
            let refresh = Task { await coordinator.refreshNow() }
            await source.waitUntilStarted()
            await scheduler.waitUntilScheduled(for: .claude)

            await scheduler.fire(.claude)
            for _ in 0..<100 { await Task.yield() }
            let completedBeforeSourceReturned = await !coordinator.isRefreshing
            await source.release()
            await refresh.value

            try TestSupport.assertEqual(completedBeforeSourceReturned, true)
        },
    ]

    private static func quota(provider: ProviderID, accountID: String) -> ProviderQuota {
        ProviderQuota(
            providerID: provider,
            accounts: [
                QuotaAccount(
                    id: accountID,
                    alias: "",
                    isActive: true,
                    state: .fresh,
                    limits: []
                )
            ]
        )
    }
}

private actor ReleasableQuotaSource: QuotaSource {
    nonisolated let sourceID = QuotaSourceID.cswap
    nonisolated let providerID = ProviderID.claude
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = false

    func fetch() async throws -> ProviderQuota {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation = $0 }
        return ProviderQuota(providerID: .claude, accounts: [])
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

actor SequencedQuotaSource: QuotaSource {
    nonisolated let sourceID: QuotaSourceID
    nonisolated let providerID: ProviderID
    private var outcomes: [Result<ProviderQuota, FixtureQuotaFetchError>]

    init(
        sourceID: QuotaSourceID,
        providerID: ProviderID,
        outcomes: [Result<ProviderQuota, FixtureQuotaFetchError>]
    ) {
        self.sourceID = sourceID
        self.providerID = providerID
        self.outcomes = outcomes
    }

    func fetch() async throws -> ProviderQuota {
        guard !outcomes.isEmpty else {
            throw FixtureQuotaFetchError.fixture("missing outcome")
        }
        return try outcomes.removeFirst().get()
    }
}
