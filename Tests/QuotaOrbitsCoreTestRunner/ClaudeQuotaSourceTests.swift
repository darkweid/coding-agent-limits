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
            try TestSupport.assertEqual(accounts[0].fiveHour?.remainingPercent, 100)
            try TestSupport.assertEqual(accounts[0].weekly?.remainingPercent, 81)
            try TestSupport.assertEqual(accounts[1].fiveHour?.remainingPercent, 28)
            try TestSupport.assertEqual(accounts[1].weekly?.remainingPercent, 93)
            try TestSupport.assertEqual(await runner.lastExecutable, executable)
            try TestSupport.assertEqual(await runner.lastArguments, ["list", "--json"])
        },
        TestCase(name: "ClaudeQuotaSourceTests.testFetchMapsScopedLimitsPerAccount") {
            let data = try TestSupport.fixtureData("cswap-list.json")
            let source = ClaudeQuotaSource(
                executable: URL(fileURLWithPath: "/fake/cswap"),
                runner: MockCommandRunner(
                    result: CommandResult(stdout: data, stderr: Data(), exitCode: 0)
                )
            )

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts[0].scoped.map(\.label), ["Fable", "Other"])
            try TestSupport.assertEqual(accounts[0].scoped.map(\.window.usedPercent), [79, 25])
            try TestSupport.assertEqual(accounts[1].scoped, [])
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
        TestCase(name: "ClaudeQuotaSourceTests.testOneAccountAndWholeSecondResetAreAccepted") {
            let source = sourceReturningOneAccount()

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts.count, 1)
            try TestSupport.assertEqual(accounts[0].alias, "max")
            try TestSupport.assertEqual(
                accounts[0].fiveHour?.resetsAt,
                Date(timeIntervalSince1970: 1_786_105_800)
            )
        },
        TestCase(name: "ClaudeQuotaSourceTests.testMissingFiveHourResetKeepsAccountAvailable") {
            let source = sourceReturningMissingFiveHourReset()

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts.count, 1)
            try TestSupport.assertEqual(accounts[0].fiveHour?.usedPercent, 100)
            try TestSupport.assertEqual(accounts[0].fiveHour?.resetsAt, nil)
            try TestSupport.assertEqual(accounts[0].weekly?.usedPercent, 19)
        },
        TestCase(name: "ClaudeQuotaSourceTests.testMissingSevenDayWindowKeepsFiveHourDataAvailable")
        {
            let source = sourceReturningMissingSevenDayWindow()

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts.count, 1)
            try TestSupport.assertEqual(accounts[0].fiveHour?.usedPercent, 38)
            try TestSupport.assertEqual(accounts[0].weekly, nil)
            try TestSupport.assertEqual(accounts[0].state, .fresh)
        },
        TestCase(name: "ClaudeQuotaSourceTests.testMissingFiveHourWindowKeepsSevenDayDataAvailable")
        {
            let source = sourceReturningMissingFiveHourWindow()

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts.count, 1)
            try TestSupport.assertEqual(accounts[0].fiveHour, nil)
            try TestSupport.assertEqual(accounts[0].weekly?.usedPercent, 62)
            try TestSupport.assertEqual(accounts[0].state, .fresh)
        },
        TestCase(
            name:
                "ClaudeQuotaSourceTests.testUnavailableAccountUsesLastGoodUsageWithoutBlockingFreshAccounts"
        ) {
            let source = sourceReturningMixedCurrentAndLastGoodUsage()

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts.map(\.alias), ["max", "pro"])
            try TestSupport.assertEqual(accounts[0].fiveHour?.usedPercent, 73)
            try TestSupport.assertEqual(accounts[0].weekly?.usedPercent, 41)
            try TestSupport.assertEqual(accounts[0].scoped.map(\.label), ["Fable"])
            try TestSupport.assertEqual(
                accounts[0].state,
                .stale(lastSuccessAt: Date(timeIntervalSince1970: 1_789_286_100))
            )
            try TestSupport.assertEqual(accounts[1].fiveHour?.usedPercent, 12)
            try TestSupport.assertEqual(accounts[1].weekly?.usedPercent, 24)
            try TestSupport.assertEqual(accounts[1].state, .fresh)
        },
        TestCase(name: "ClaudeQuotaSourceTests.testAccountWithoutCurrentOrCachedUsageIsUnavailable")
        {
            let source = sourceReturningUnavailableAccountWithoutCache()

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts.count, 1)
            try TestSupport.assertEqual(accounts[0].alias, "max")
            try TestSupport.assertEqual(accounts[0].fiveHour, nil)
            try TestSupport.assertEqual(accounts[0].weekly, nil)
            try TestSupport.assertEqual(accounts[0].state, .unavailable)
        },
        TestCase(name: "ClaudeQuotaSourceTests.testFetchDoesNotTruncateAccounts") {
            let source = sourceReturningThreeAccounts()

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts.map(\.alias), ["max", "pro", "lab"])
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
        },
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
            stdout: Data(
                """
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
                          "resetsAt": "2026-08-07T12:30:00+00:00"
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

    private static func sourceReturningThreeAccounts() -> ClaudeQuotaSource {
        let result = CommandResult(
            stdout: Data(
                """
                {
                  "schemaVersion": 1,
                  "activeAccountNumber": 2,
                  "accounts": [
                    {
                      "number": 1,
                      "email": "hidden@example.invalid",
                      "active": false,
                      "usageStatus": "ok",
                      "usage": {
                        "fiveHour": { "pct": 8.0, "resetsAt": "2026-08-07T12:30:00.162124+00:00" },
                        "sevenDay": { "pct": 57.0, "resetsAt": "2026-08-12T07:00:00.162148+00:00" }
                      },
                      "alias": "max"
                    },
                    {
                      "number": 2,
                      "email": "hidden2@example.invalid",
                      "active": true,
                      "usageStatus": "ok",
                      "usage": {
                        "fiveHour": { "pct": 100.0, "resetsAt": "2026-08-07T11:50:00.774549+00:00" },
                        "sevenDay": { "pct": 73.0, "resetsAt": "2026-08-09T22:00:00.774573+00:00" }
                      },
                      "alias": "pro"
                    },
                    {
                      "number": 3,
                      "email": "hidden3@example.invalid",
                      "active": false,
                      "usageStatus": "ok",
                      "usage": {
                        "fiveHour": { "pct": 4.0, "resetsAt": "2026-08-07T13:00:00.000000+00:00" },
                        "sevenDay": { "pct": 10.0, "resetsAt": "2026-08-13T07:00:00.000000+00:00" }
                      },
                      "alias": "lab"
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

    private static func sourceReturningMissingFiveHourReset() -> ClaudeQuotaSource {
        let result = CommandResult(
            stdout: Data(
                """
                {
                  "schemaVersion": 1,
                  "activeAccountNumber": 1,
                  "accounts": [
                    {
                      "number": 1,
                      "active": true,
                      "usage": {
                        "fiveHour": { "pct": 100.0 },
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

    private static func sourceReturningMixedCurrentAndLastGoodUsage() -> ClaudeQuotaSource {
        let result = CommandResult(
            stdout: Data(
                """
                {
                  "schemaVersion": 1,
                  "activeAccountNumber": 1,
                  "accounts": [
                    {
                      "number": 1,
                      "active": true,
                      "usageStatus": "no_credentials",
                      "usage": null,
                      "lastGoodUsage": {
                        "fiveHour": { "pct": 73.0, "resetsAt": "2026-09-13T08:00:00+00:00" },
                        "sevenDay": { "pct": 41.0, "resetsAt": "2026-09-18T08:00:00+00:00" },
                        "scoped": [
                          { "name": "Fable", "pct": 16.0, "resetsAt": "2026-09-18T08:00:00+00:00" }
                        ]
                      },
                      "lastGoodFetchedAt": "2026-09-13T07:55:00+00:00",
                      "alias": "max"
                    },
                    {
                      "number": 2,
                      "active": false,
                      "usageStatus": "ok",
                      "usage": {
                        "fiveHour": { "pct": 12.0, "resetsAt": "2026-09-13T12:00:00+00:00" },
                        "sevenDay": { "pct": 24.0, "resetsAt": "2026-09-19T08:00:00+00:00" }
                      },
                      "alias": "pro"
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

    private static func sourceReturningMissingSevenDayWindow() -> ClaudeQuotaSource {
        let result = CommandResult(
            stdout: Data(
                """
                {
                  "schemaVersion": 1,
                  "activeAccountNumber": 1,
                  "accounts": [
                    {
                      "number": 1,
                      "active": true,
                      "usageStatus": "ok",
                      "usage": {
                        "fiveHour": { "pct": 38.0, "resetsAt": "2026-09-13T12:00:00+00:00" }
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

    private static func sourceReturningMissingFiveHourWindow() -> ClaudeQuotaSource {
        let result = CommandResult(
            stdout: Data(
                """
                {
                  "schemaVersion": 1,
                  "activeAccountNumber": 1,
                  "accounts": [
                    {
                      "number": 1,
                      "active": true,
                      "usageStatus": "ok",
                      "usage": {
                        "sevenDay": { "pct": 62.0, "resetsAt": "2026-09-19T08:00:00+00:00" }
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

    private static func sourceReturningUnavailableAccountWithoutCache() -> ClaudeQuotaSource {
        let result = CommandResult(
            stdout: Data(
                """
                {
                  "schemaVersion": 1,
                  "activeAccountNumber": 1,
                  "accounts": [
                    {
                      "number": 1,
                      "active": true,
                      "usageStatus": "no_credentials",
                      "usage": null,
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
