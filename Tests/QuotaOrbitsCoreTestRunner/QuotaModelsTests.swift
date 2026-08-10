import Foundation
import QuotaOrbitsCore

enum QuotaModelsTests {
    static let cases: [TestCase] = [
        TestCase(name: "QuotaModelsTests.testNeutralLimitClampsAndDerivesPresentationValues") {
            let reset = Date(timeIntervalSince1970: 2_000)
            let limit = QuotaLimit(
                id: "weekly",
                label: "Weekly",
                usedPercent: 72,
                resetsAt: reset
            )

            try TestSupport.assertEqual(limit.usedPercent, 72)
            try TestSupport.assertEqual(limit.remainingPercent, 28)
            try TestSupport.assertEqual(limit.level, .warning)
            try TestSupport.assertEqual(limit.resetsAt, reset)
            try TestSupport.assertEqual(
                QuotaLimit(id: "low", label: "Low", usedPercent: -1, resetsAt: reset)
                    .usedPercent,
                0
            )
            try TestSupport.assertEqual(
                QuotaLimit(id: "high", label: "High", usedPercent: 101, resetsAt: reset)
                    .remainingPercent,
                0
            )
        },
        TestCase(name: "QuotaModelsTests.testNeutralQuotaPreservesSourceOrderAndIdentity") {
            let limit = QuotaLimit(
                id: "five-hour",
                label: "5h",
                usedPercent: 10,
                resetsAt: .distantFuture
            )
            let accounts = [
                QuotaAccount(
                    id: "2",
                    alias: "second",
                    isActive: false,
                    state: .unavailable,
                    limits: []
                ),
                QuotaAccount(
                    id: "1",
                    alias: "first",
                    isActive: true,
                    state: .fresh,
                    limits: [limit]
                ),
            ]
            let quota = ProviderQuota(
                providerID: .claude,
                accounts: accounts,
                balances: [QuotaBalance(label: "Credits", amount: 12, currencyCode: nil)]
            )

            try TestSupport.assertEqual(quota.providerID, .claude)
            try TestSupport.assertEqual(quota.accounts.map(\.id), ["2", "1"])
            try TestSupport.assertEqual(quota.accounts[1].limits, [limit])
            try TestSupport.assertEqual(quota.balances[0].amount, 12)
            try TestSupport.assertFalse(QuotaSourceID.cswap == QuotaSourceID.claudeCode)
        },
        TestCase(name: "QuotaModelsTests.testUsedQuotaLevelBoundaries") {
            try TestSupport.assertEqual(
                QuotaLevel.classify(usedPercent: nil),
                .unavailable
            )
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 0), .healthy)
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 70), .healthy)
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 70.01), .warning)
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 85), .warning)
            try TestSupport.assertEqual(
                QuotaLevel.classify(usedPercent: 85.01),
                .critical
            )
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 100), .critical)
        },
    ]
}
