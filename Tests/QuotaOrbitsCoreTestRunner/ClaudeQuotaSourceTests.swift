import Foundation
import QuotaOrbitsCore

enum ClaudeQuotaSourceTests {
    static let cases: [TestCase] = [
        TestCase(name: "ClaudeQuotaSourceTests.testFetchUsesJSONCommandAndMapsTwoAccounts") {
            let data = try TestSupport.fixtureData("cswap-list.json")
            let runner = MockCommandRunner(
                result: CommandResult(stdout: data, stderr: Data(), exitCode: 0)
            )
            let executable = URL(fileURLWithPath: "/fake/cswap")
            let source = ClaudeQuotaSource(executable: executable, runner: runner)

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts.map(\.alias), ["max", "pro"])
            try TestSupport.assertEqual(accounts[0].fiveHour.remainingPercent, 100)
            try TestSupport.assertEqual(accounts[0].weekly.remainingPercent, 81)
            try TestSupport.assertEqual(accounts[1].fiveHour.remainingPercent, 28)
            try TestSupport.assertEqual(accounts[1].weekly.remainingPercent, 93)
            try TestSupport.assertEqual(await runner.lastExecutable, executable)
            try TestSupport.assertEqual(await runner.lastArguments, ["list", "--json"])
        },
        TestCase(name: "ClaudeQuotaSourceTests.testMissingAliasFallsBackToTwoDigitSlot") {
            let data = try fixtureWithFirstAliasRemoved()
            let source = ClaudeQuotaSource(
                executable: URL(fileURLWithPath: "/fake/cswap"),
                runner: MockCommandRunner(
                    result: CommandResult(stdout: data, stderr: Data(), exitCode: 0)
                )
            )

            try TestSupport.assertEqual(try await source.fetch().first?.alias, "01")
        },
        TestCase(name: "ClaudeQuotaSourceTests.testLessThanTwoAccountsIsRejected") {
            let source = sourceReturningOneAccount()

            try await TestSupport.assertThrowsErrorAsync(try await source.fetch()) { error in
                try TestSupport.assertEqual(
                    error as? ClaudeQuotaError,
                    .expectedTwoAccounts(actual: 1)
                )
            }
        },
        TestCase(name: "ClaudeQuotaSourceTests.testNonzeroExitDoesNotExposeStderr") {
            let source = sourceReturningFailure(
                exitCode: 1,
                stderr: Data("token=secret".utf8)
            )

            try await TestSupport.assertThrowsErrorAsync(try await source.fetch()) { error in
                try TestSupport.assertEqual(
                    error as? ClaudeQuotaError,
                    .commandFailed(exitCode: 1)
                )
                try TestSupport.assertFalse(String(describing: error).contains("secret"))
            }
        },
        TestCase(name: "ClaudeQuotaSourceTests.testRealRunnerCapturesStdout") {
            let result = try await ProcessCommandRunner().run(
                executable: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["ok"],
                timeout: .seconds(1)
            )

            try TestSupport.assertEqual(String(decoding: result.stdout, as: UTF8.self), "ok")
            try TestSupport.assertEqual(result.exitCode, 0)
        },
        TestCase(name: "ClaudeQuotaSourceTests.testRealRunnerDrainsLargeStdoutBeforeTimeout") {
            let result = try await ProcessCommandRunner().run(
                executable: URL(fileURLWithPath: CommandLine.arguments[0]),
                arguments: ["--emit-large-payload"],
                timeout: .seconds(1)
            )

            try TestSupport.assertEqual(result.stdout.count, 1_000_000)
            try TestSupport.assertEqual(result.exitCode, 0)
        },
        TestCase(name: "ClaudeQuotaSourceTests.testRealRunnerTerminatesAfterTimeout") {
            try await TestSupport.assertThrowsErrorAsync(
                try await ProcessCommandRunner().run(
                    executable: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["2"],
                    timeout: .milliseconds(50)
                )
            ) { error in
                try TestSupport.assertEqual(error as? CommandRunnerError, .timedOut)
            }
        }
    ]

    private static func fixtureWithFirstAliasRemoved() throws -> Data {
        let fixture = try TestSupport.fixtureData("cswap-list.json")
        let text = String(decoding: fixture, as: UTF8.self)
            .replacingOccurrences(
                of: "      },\n      \"alias\": \"max\"\n",
                with: "      }\n"
            )
        return Data(text.utf8)
    }

    private static func sourceReturningOneAccount() -> ClaudeQuotaSource {
        let result = CommandResult(
            stdout: Data("""
            {
              "schemaVersion": 1,
              "activeAccountNumber": 1,
              "accounts": [
                {
                  "number": 1,
                  "email": "hidden@example.invalid",
                  "active": true,
                  "usageStatus": "ok",
                  "usage": {
                    "fiveHour": {
                      "pct": 0.0,
                      "resetsAt": "2026-08-07T12:30:00.162124+00:00"
                    },
                    "sevenDay": {
                      "pct": 19.0,
                      "resetsAt": "2026-08-12T07:00:00.162148+00:00"
                    }
                  },
                  "alias": "max"
                }
              ]
            }
            """.utf8),
            stderr: Data(),
            exitCode: 0
        )
        return ClaudeQuotaSource(
            executable: URL(fileURLWithPath: "/fake/cswap"),
            runner: MockCommandRunner(result: result)
        )
    }

    private static func sourceReturningFailure(
        exitCode: Int32,
        stderr: Data
    ) -> ClaudeQuotaSource {
        ClaudeQuotaSource(
            executable: URL(fileURLWithPath: "/fake/cswap"),
            runner: MockCommandRunner(
                result: CommandResult(stdout: Data(), stderr: stderr, exitCode: exitCode)
            )
        )
    }
}
