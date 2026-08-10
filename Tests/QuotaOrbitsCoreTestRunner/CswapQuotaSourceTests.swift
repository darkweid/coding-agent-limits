import Foundation
import QuotaOrbitsCore

enum CswapQuotaSourceTests {
    static let cases: [TestCase] = [
        TestCase(name: "CswapQuotaSourceTests.testMapsEveryAccountAndScopedLimit") {
            let runner = MockCommandRunner(
                result: CommandResult(
                    stdout: Data(cswapPayloadWithScopedLimits.utf8),
                    stderr: Data(),
                    exitCode: 0
                )
            )
            let executable = URL(fileURLWithPath: "/fake/cswap")
            let source = CswapQuotaSource(executable: executable, runner: runner)

            let quota = try await source.fetch()

            try TestSupport.assertEqual(quota.providerID, .claude)
            try TestSupport.assertEqual(quota.accounts.map(\.id), ["1", "2", "3"])
            try TestSupport.assertEqual(
                quota.accounts[0].limits.map(\.label),
                ["5 hours", "Weekly", "Fable", "Opus"]
            )
            try TestSupport.assertEqual(
                quota.accounts[0].limits.map(\.usedPercent), [8, 57, 44, 12]
            )
            try TestSupport.assertEqual(await runner.lastExecutable, executable)
            try TestSupport.assertEqual(await runner.lastArguments, ["list", "--json"])
        },
        TestCase(name: "CswapQuotaSourceTests.testKeepsFreshStaleAndUnavailableSiblings") {
            let source = CswapQuotaSource(
                executable: URL(fileURLWithPath: "/fake/cswap"),
                runner: MockCommandRunner(
                    result: CommandResult(
                        stdout: Data(cswapMixedStatePayload.utf8),
                        stderr: Data(),
                        exitCode: 0
                    )
                )
            )

            let accounts = try await source.fetch().accounts

            try TestSupport.assertEqual(
                accounts.map(\.state),
                [
                    .fresh,
                    .stale(lastSuccessAt: Date(timeIntervalSince1970: 1_786_106_000)),
                    .unavailable,
                ]
            )
            try TestSupport.assertEqual(
                accounts[1].limits.map(\.label), ["5 hours", "Weekly", "Fable"]
            )
            try TestSupport.assertEqual(accounts[2].limits, [])
        },
        TestCase(name: "CswapQuotaSourceTests.testFailureDoesNotExposeCommandOutput") {
            let source = CswapQuotaSource(
                executable: URL(fileURLWithPath: "/fake/cswap"),
                runner: MockCommandRunner(
                    result: CommandResult(
                        stdout: Data(),
                        stderr: Data("token=secret".utf8),
                        exitCode: 1
                    )
                )
            )

            try await TestSupport.assertThrowsErrorAsync(try await source.fetch()) { error in
                try TestSupport.assertEqual(error as? CswapQuotaError, .commandFailed(exitCode: 1))
                try TestSupport.assertFalse(String(describing: error).contains("secret"))
            }
        },
        TestCase(name: "ProcessCommandRunnerTests.testCapturesStdout") {
            let result = try await ProcessCommandRunner().run(
                executable: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["ok"],
                timeout: .seconds(1)
            )

            try TestSupport.assertEqual(String(decoding: result.stdout, as: UTF8.self), "ok")
            try TestSupport.assertEqual(result.exitCode, 0)
        },
        TestCase(name: "ProcessCommandRunnerTests.testDrainsLargeStdoutBeforeTimeout") {
            let result = try await ProcessCommandRunner().run(
                executable: URL(fileURLWithPath: CommandLine.arguments[0]),
                arguments: ["--emit-large-payload"],
                timeout: .seconds(1)
            )

            try TestSupport.assertEqual(result.stdout.count, 1_000_000)
            try TestSupport.assertEqual(result.exitCode, 0)
        },
        TestCase(name: "ProcessCommandRunnerTests.testTerminatesAfterTimeout") {
            try await TestSupport.assertThrowsErrorAsync(
                try await ProcessCommandRunner().run(
                    executable: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["2"],
                    timeout: .milliseconds(50)
                )
            ) { error in
                try TestSupport.assertEqual(error as? CommandRunnerError, .timedOut)
            }
        },
    ]

    private static let cswapPayloadWithScopedLimits = """
        {
          "schemaVersion": 1,
          "accounts": [
            {"number":1,"active":false,"usageStatus":"ok","usage":{
              "fiveHour":{"pct":8,"resetsAt":"2026-08-07T12:30:00Z"},
              "sevenDay":{"pct":57,"resetsAt":"2026-08-12T07:00:00Z"},
              "scoped":[
                {"name":"Fable","pct":44,"resetsAt":"2026-08-12T07:00:00Z"},
                {"name":"Opus","pct":12,"resetsAt":"2026-08-12T07:00:00Z"}
              ]},"alias":"one"},
            {"number":2,"active":true,"usageStatus":"ok","usage":{
              "fiveHour":{"pct":2,"resetsAt":"2026-08-07T12:30:00Z"},
              "sevenDay":{"pct":3,"resetsAt":"2026-08-12T07:00:00Z"}}},
            {"number":3,"active":false,"usageStatus":"ok","usage":{
              "fiveHour":{"pct":4,"resetsAt":"2026-08-07T12:30:00Z"},
              "sevenDay":{"pct":5,"resetsAt":"2026-08-12T07:00:00Z"}}}
          ]
        }
        """

    private static let cswapMixedStatePayload = """
        {
          "schemaVersion": 1,
          "accounts": [
            {"number":1,"active":true,"usageStatus":"ok","usage":{
              "fiveHour":{"pct":8,"resetsAt":"2026-08-07T12:30:00Z"},
              "sevenDay":{"pct":57,"resetsAt":"2026-08-12T07:00:00Z"}}},
            {"number":2,"active":false,"usageStatus":"unavailable","usage":null,
              "lastGoodFetchedAt":"2026-08-07T12:33:20Z","lastGoodUsage":{
                "fiveHour":{"pct":20,"resetsAt":"2026-08-07T13:30:00Z"},
                "sevenDay":{"pct":30,"resetsAt":"2026-08-12T07:00:00Z"},
                "scoped":[{"name":"Fable","pct":40,"resetsAt":"2026-08-12T07:00:00Z"}]}},
            {"number":3,"active":false,"usageStatus":"unavailable","usage":null}
          ]
        }
        """
}
