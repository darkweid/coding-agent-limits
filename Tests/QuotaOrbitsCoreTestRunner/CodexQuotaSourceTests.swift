import Foundation
import QuotaOrbitsCore

enum CodexQuotaSourceTests {
    static let cases: [TestCase] = [
        TestCase(name: "CodexQuotaSourceTests.testFetchMapsNamedFiveHourAndWeeklyWindows") {
            let response = Data(
                #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300,"resetsAt":100}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":60,"windowDurationMins":10080,"resetsAt":300},"secondary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":200}}}}}"#
                    .utf8)

            let quota = try await source(response: response).fetch()

            try TestSupport.assertEqual(quota.fiveHour?.remainingPercent, 75)
            try TestSupport.assertEqual(
                quota.fiveHour?.resetsAt,
                Date(timeIntervalSince1970: 200)
            )
            try TestSupport.assertEqual(quota.weekly.remainingPercent, 40)
            try TestSupport.assertEqual(quota.weekly.resetsAt, Date(timeIntervalSince1970: 300))
        },
        TestCase(name: "CodexQuotaSourceTests.testFetchFallsBackToLegacyRateLimits") {
            let response = Data(
                #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":300}}}}"#
                    .utf8)

            let quota = try await source(response: response).fetch()

            try TestSupport.assertEqual(quota.fiveHour, nil)
            try TestSupport.assertEqual(quota.weekly.remainingPercent, 60)
            try TestSupport.assertEqual(quota.weekly.resetsAt, Date(timeIntervalSince1970: 300))
        },
        TestCase(name: "CodexQuotaSourceTests.testFetchIgnoresIncompleteSecondaryWindow") {
            let response = Data(
                #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":300},"secondary":{"usedPercent":10}}}}"#
                    .utf8)

            let quota = try await source(response: response).fetch()

            try TestSupport.assertEqual(quota.fiveHour, nil)
            try TestSupport.assertEqual(quota.weekly.remainingPercent, 60)
            try TestSupport.assertEqual(quota.weekly.resetsAt, Date(timeIntervalSince1970: 300))
        },
        TestCase(name: "CodexQuotaSourceTests.testFetchDecodesDecimalCreditsAndUnixReset") {
            let fixture = try TestSupport.fixtureData("codex-rate-limits.json")

            let quota = try await source(response: fixture).fetch()

            try TestSupport.assertEqual(
                quota.creditsBalance,
                Decimal(string: "411.5127706250")
            )
            try TestSupport.assertEqual(
                quota.fiveHour?.resetsAt,
                Date(timeIntervalSince1970: 1_785_741_033)
            )
            try TestSupport.assertEqual(
                quota.weekly.resetsAt,
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

    private static func source(response: Data) -> CodexQuotaSource {
        let initialize = Data(#"{"id":1,"result":{"userAgent":"test"}}"#.utf8)
        return CodexQuotaSource(
            client: CodexAppServerClient(
                transport: ScriptedJSONLineTransport(responses: [initialize, response])
            )
        )
    }
}
