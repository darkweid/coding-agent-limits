import Foundation
import QuotaOrbitsCore

enum ClaudeCodeQuotaSourceTests {
    static let cases: [TestCase] = [
        TestCase(name: "ClaudeCodeQuotaSourceTests.testRealPTYCapturesInteractiveUsage") {
            let transcript = try await ClaudeUsageTerminalSession().captureUsage(
                executable: URL(fileURLWithPath: CommandLine.arguments[0]),
                arguments: ["--emit-usage-pty"],
                timeout: .seconds(2),
                maximumOutputBytes: ClaudeUsageTerminalParser.maximumOutputBytes
            )

            try TestSupport.assertEqual(
                String(decoding: transcript, as: UTF8.self).contains("Current week (all models)"),
                true
            )
        },
        TestCase(name: "ClaudeCodeQuotaSourceTests.testMapsTerminalUsageToOneActiveAccount") {
            let runner = StubClaudeUsageTerminalRunner(
                result: .success(Data(nativeUsageTranscript.utf8))
            )
            let source = ClaudeCodeQuotaSource(
                executable: URL(fileURLWithPath: "/fake/claude"),
                terminalRunner: runner,
                now: { Date(timeIntervalSince1970: 1_786_335_600) }
            )

            let quota = try await source.fetch()

            try TestSupport.assertEqual(quota.providerID, .claude)
            try TestSupport.assertEqual(quota.accounts.count, 1)
            try TestSupport.assertEqual(quota.accounts[0].alias, "")
            try TestSupport.assertEqual(quota.accounts[0].isActive, true)
            try TestSupport.assertEqual(quota.accounts[0].state, .fresh)
            try TestSupport.assertEqual(quota.accounts[0].limits.map(\.usedPercent), [9, 79, 12])
        },
        TestCase(name: "ClaudeCodeQuotaSourceTests.testSanitizesTerminalFailure") {
            let source = ClaudeCodeQuotaSource(
                executable: URL(fileURLWithPath: "/fake/claude"),
                terminalRunner: StubClaudeUsageTerminalRunner(
                    result: .failure(.launchFailed)
                )
            )

            try await TestSupport.assertThrowsErrorAsync(try await source.fetch()) { error in
                try TestSupport.assertEqual(
                    error as? ClaudeCodeQuotaError,
                    .terminalUnavailable
                )
                try TestSupport.assertFalse(String(describing: error).contains("/fake/claude"))
            }
        },
    ]

    private static let nativeUsageTranscript = """
        Current session
        9% used
        Resets 11:59pm (America/New_York)
        Current week (all models)
        79% used
        Resets Aug 14 at 10:59am (America/New_York)
        Current week (Fable)
        12% used
        Esc to exit
        """
}

actor StubClaudeUsageTerminalRunner: ClaudeUsageTerminalRunning {
    let result: Result<Data, ClaudeUsageTerminalError>

    init(result: Result<Data, ClaudeUsageTerminalError>) {
        self.result = result
    }

    func captureUsage(
        executable: URL,
        arguments: [String],
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> Data {
        try result.get()
    }
}
