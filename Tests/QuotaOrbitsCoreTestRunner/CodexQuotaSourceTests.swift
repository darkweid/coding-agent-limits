import Foundation
import QuotaOrbitsCore

enum CodexQuotaSourceTests {
    static let cases: [TestCase] = [
        TestCase(name: "CodexQuotaSourceTests.testNeutralSourceMapsWeeklyWindowAndCreditsOnly") {
            let response = Data(
                #"{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":200},"credits":{"balance":"12.5"}}}}}"#
                    .utf8)
            let initialize = Data(#"{"id":1,"result":{"userAgent":"test"}}"#.utf8)
            let quotaSource = source(response: response, initialize: initialize)

            let quota = try await quotaSource.fetch()

            try TestSupport.assertEqual(quota.providerID, .codex)
            try TestSupport.assertEqual(quota.accounts.count, 1)
            try TestSupport.assertEqual(quota.accounts[0].limits.map(\.id), ["weekly"])
            try TestSupport.assertEqual(quota.accounts[0].limits[0].remainingPercent, 75)
            try TestSupport.assertEqual(
                quota.balances,
                [QuotaBalance(label: "Credits", amount: 12.5, currencyCode: nil)]
            )
        },
        TestCase(name: "CodexQuotaSourceTests.testFetchPrefersNamedCodexBucket") {
            let response = Data(
                #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300,"resetsAt":100}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":200}}}}}"#
                    .utf8)

            let quota = try await source(response: response).fetch()
            let weekly = quota.accounts[0].limits[0]

            try TestSupport.assertEqual(weekly.remainingPercent, 75)
            try TestSupport.assertEqual(weekly.resetsAt, Date(timeIntervalSince1970: 200))
        },
        TestCase(name: "CodexQuotaSourceTests.testFetchFallsBackToLegacyRateLimits") {
            let response = Data(
                #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":300}}}}"#
                    .utf8)

            let quota = try await source(response: response).fetch()
            let weekly = quota.accounts[0].limits[0]

            try TestSupport.assertEqual(weekly.remainingPercent, 60)
            try TestSupport.assertEqual(weekly.resetsAt, Date(timeIntervalSince1970: 300))
        },
        TestCase(name: "CodexQuotaSourceTests.testFetchDecodesDecimalCreditsAndUnixReset") {
            let fixture = try TestSupport.fixtureData("codex-rate-limits.json")

            let quota = try await source(response: fixture).fetch()

            try TestSupport.assertEqual(
                quota.balances.first?.amount, Decimal(string: "411.5127706250"))
            try TestSupport.assertEqual(
                quota.accounts[0].limits[0].resetsAt,
                Date(timeIntervalSince1970: 1_786_342_233)
            )
        },
        TestCase(name: "CodexQuotaSourceTests.testFetchRejectsMissingPrimary") {
            let response = Data(
                #"{"id":2,"result":{"rateLimits":{"credits":{"balance":"99"}}}}"#.utf8)

            try await TestSupport.assertThrowsErrorAsync(
                try await source(response: response).fetch()
            ) { error in
                try TestSupport.assertEqual(
                    error as? CodexQuotaError,
                    .missingPrimaryWindow
                )
            }
        },
        TestCase(name: "CodexQuotaSourceTests.testMalformedResponseErrorIsSanitized") {
            let response = Data(
                #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":"token=super-secret","windowDurationMins":10080,"resetsAt":300}}}}"#
                    .utf8)

            try await TestSupport.assertThrowsErrorAsync(
                try await source(response: response).fetch()
            ) { error in
                try TestSupport.assertEqual(error as? CodexQuotaError, .invalidResponse)
                try TestSupport.assertFalse(
                    String(describing: error).contains("super-secret")
                )
            }
        },
    ]

    private static func source(
        response: Data,
        initialize: Data = Data(#"{"id":1,"result":{"userAgent":"test"}}"#.utf8)
    ) -> CodexAppServerQuotaSource {
        CodexAppServerQuotaSource(
            client: CodexAppServerClient(
                transport: ScriptedJSONLineTransport(responses: [initialize, response])
            )
        )
    }
}
