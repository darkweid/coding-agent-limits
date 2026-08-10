import Foundation
@_spi(Testing) import QuotaOrbitsCore

enum ReplaceableQuotaSourceTests {
    static let cases: [TestCase] = [
        TestCase(name: "ReplaceableQuotaSourceTests.testRejectsStaleGeneration") {
            let initialCleanup = CleanupProbe()
            let staleCleanup = CleanupProbe()
            let slot = ReplaceableQuotaSource(
                source: source(marker: "initial"),
                cleanup: { await initialCleanup.run() }
            )
            await slot.replace(
                with: source(marker: "new", sourceID: .claudeCode),
                generation: 2
            )
            await slot.replace(
                with: source(marker: "stale"),
                generation: 1,
                cleanup: { await staleCleanup.run() }
            )

            try TestSupport.assertEqual(try await slot.fetch().accounts[0].id, "new")
            try TestSupport.assertEqual(await initialCleanup.count, 1)
            try TestSupport.assertEqual(await staleCleanup.count, 1)
        }
    ]

    private static func source(
        marker: String,
        sourceID: QuotaSourceID = .cswap
    ) -> SequencedQuotaSource {
        SequencedQuotaSource(
            sourceID: sourceID,
            providerID: .claude,
            outcomes: [
                .success(
                    ProviderQuota(
                        providerID: .claude,
                        accounts: [
                            QuotaAccount(
                                id: marker,
                                alias: "",
                                isActive: true,
                                state: .fresh,
                                limits: []
                            )
                        ]
                    )
                )
            ]
        )
    }
}

private actor CleanupProbe {
    private(set) var count = 0

    func run() {
        count += 1
    }
}
