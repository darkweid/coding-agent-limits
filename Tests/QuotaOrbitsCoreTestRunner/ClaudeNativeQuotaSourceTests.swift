import Foundation
@_spi(Testing) import QuotaOrbitsCore

enum ClaudeNativeQuotaSourceTests {
    static let cases: [TestCase] = [
        TestCase(name: "ClaudeNativeQuotaSourceTests.testUsageConversationWaitsForReadyPrompt") {
            var conversation = ClaudeUsageTerminalConversation()

            try TestSupport.assertEqual(
                conversation.receive(Data("Starting Claude Code".utf8)),
                nil
            )
            try TestSupport.assertEqual(
                conversation.receive(Data("❯".utf8)),
                .requestUsage
            )
            try TestSupport.assertEqual(
                conversation.receive(Data("❯".utf8)),
                nil
            )
            try TestSupport.assertEqual(
                conversation.receive(Data("Esc\u{1B}[1Cto\u{1B}[1Cexit".utf8)),
                .usageComplete
            )
        },
        TestCase(name: "ClaudeNativeQuotaSourceTests.testUsageConversationAcceptsOwnedWorkspace") {
            var conversation = ClaudeUsageTerminalConversation()

            try TestSupport.assertEqual(
                conversation.receive(
                    Data("Workspace trust security\n❯ Yes, I trust this folder".utf8)
                ),
                .acceptWorkspaceTrust
            )
            try TestSupport.assertEqual(
                conversation.receive(Data("❯ Yes, I trust this folder".utf8)),
                nil
            )
            conversation.didSubmitWorkspaceTrustAcceptance()
            try TestSupport.assertEqual(
                conversation.receive(Data("❯".utf8)),
                .requestUsage
            )
        },
        TestCase(name: "ClaudeNativeQuotaSourceTests.testUsageConversationDetectsRateLimit") {
            var conversation = ClaudeUsageTerminalConversation()
            _ = conversation.receive(Data("❯".utf8))

            try TestSupport.assertEqual(
                conversation.receive(
                    Data("Usage endpoint\u{1B}[1Cis\u{1B}[1Crate\u{1B}[1Climited".utf8)
                ),
                .usageUnavailable
            )
        },
        TestCase(
            name: "ClaudeNativeQuotaSourceTests.testUsageConversationCompletesWhileInsightsRefresh"
        ) {
            var conversation = ClaudeUsageTerminalConversation()
            _ = conversation.receive(Data("❯".utf8))
            let pendingInsights = String(
                repeating: "Scanning local sessions…\n",
                count: 80
            )

            try TestSupport.assertEqual(
                conversation.receive(
                    Data(
                        """
                        Current session
                        21% used
                        Resets 6:20pm (Asia/Tashkent)
                        Current week (all models)
                        2% used
                        Resets Sep 21 at 3am (Asia/Tashkent)
                        \(pendingInsights)
                        Refreshing…
                        Esc to cancel
                        """.utf8
                    )
                ),
                .usageComplete
            )
        },
        TestCase(name: "ClaudeNativeQuotaSourceTests.testRealPTYHandlesWorkspaceTrust") {
            let transcript = try await ClaudeUsageTerminalSession().captureUsage(
                executable: URL(fileURLWithPath: CommandLine.arguments[0]),
                arguments: ["--emit-trust-usage-pty"],
                workingDirectory: FileManager.default.temporaryDirectory,
                timeout: .seconds(2),
                maximumOutputBytes: ClaudeUsageTerminalParser.maximumOutputBytes
            )

            try TestSupport.assertEqual(
                String(decoding: transcript, as: UTF8.self).contains("Current session"),
                true
            )
        },
        TestCase(name: "ClaudeNativeQuotaSourceTests.testRealPTYCapturesInteractiveUsage") {
            let transcript = try await ClaudeUsageTerminalSession().captureUsage(
                executable: URL(fileURLWithPath: CommandLine.arguments[0]),
                arguments: ["--emit-usage-pty"],
                workingDirectory: FileManager.default.temporaryDirectory,
                timeout: .seconds(2),
                maximumOutputBytes: ClaudeUsageTerminalParser.maximumOutputBytes
            )

            try TestSupport.assertEqual(
                String(decoding: transcript, as: UTF8.self).contains("Current week (all models)"),
                true
            )
        },
        TestCase(name: "ClaudeNativeQuotaSourceTests.testRealPTYUsesStableViewport") {
            let transcript = try await ClaudeUsageTerminalSession().captureUsage(
                executable: URL(fileURLWithPath: CommandLine.arguments[0]),
                arguments: ["--emit-terminal-size-usage-pty"],
                workingDirectory: FileManager.default.temporaryDirectory,
                timeout: .seconds(2),
                maximumOutputBytes: ClaudeUsageTerminalParser.maximumOutputBytes
            )

            try TestSupport.assertEqual(
                String(decoding: transcript, as: UTF8.self).contains("viewport 60x120"),
                true
            )
        },
        TestCase(name: "ClaudeNativeQuotaSourceTests.testMapsUsageToOneActiveAccount") {
            let source = ClaudeNativeQuotaSource(
                executable: URL(fileURLWithPath: "/fake/claude"),
                terminalRunner: StubClaudeUsageTerminalRunner(
                    result: .success(Data(nativeUsageTranscript.utf8))
                ),
                now: { Date(timeIntervalSince1970: 1_786_335_600) }
            )

            let accounts = try await source.fetch()

            try TestSupport.assertEqual(accounts.count, 1)
            try TestSupport.assertEqual(accounts[0].alias, "native")
            try TestSupport.assertEqual(accounts[0].isActive, true)
            try TestSupport.assertEqual(accounts[0].state, .fresh)
            try TestSupport.assertEqual(accounts[0].fiveHour?.usedPercent, 9)
            try TestSupport.assertEqual(accounts[0].weekly?.usedPercent, 79)
            try TestSupport.assertEqual(accounts[0].scoped.map(\.label), ["Fable"])
            try TestSupport.assertEqual(accounts[0].scoped.map(\.window.usedPercent), [12])
        },
        TestCase(name: "ClaudeNativeQuotaSourceTests.testUsesDedicatedWorkspace") {
            let workspace = URL(fileURLWithPath: "/isolated/native-claude", isDirectory: true)
            let runner = RecordingClaudeUsageTerminalRunner(
                result: .success(Data(nativeUsageTranscript.utf8))
            )
            let source = ClaudeNativeQuotaSource(
                executable: URL(fileURLWithPath: "/fake/claude"),
                terminalRunner: runner,
                workingDirectory: workspace,
                now: { Date(timeIntervalSince1970: 1_786_335_600) }
            )

            _ = try await source.fetch()

            try await TestSupport.assertEqual(
                runner.capturedWorkingDirectory,
                workspace
            )
        },
        TestCase(name: "ClaudeNativeQuotaSourceTests.testSanitizesTerminalFailure") {
            let source = ClaudeNativeQuotaSource(
                executable: URL(fileURLWithPath: "/private/claude"),
                terminalRunner: StubClaudeUsageTerminalRunner(
                    result: .failure(.launchFailed)
                )
            )

            try await TestSupport.assertThrowsErrorAsync(try await source.fetch()) { error in
                try TestSupport.assertEqual(
                    error as? ClaudeNativeQuotaError,
                    .terminalUnavailable
                )
                try TestSupport.assertFalse(String(describing: error).contains("/private/claude"))
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
        workingDirectory: URL,
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> Data {
        try result.get()
    }
}

actor RecordingClaudeUsageTerminalRunner: ClaudeUsageTerminalRunning {
    let result: Result<Data, ClaudeUsageTerminalError>
    private(set) var capturedWorkingDirectory: URL?

    init(result: Result<Data, ClaudeUsageTerminalError>) {
        self.result = result
    }

    func captureUsage(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> Data {
        capturedWorkingDirectory = workingDirectory
        return try result.get()
    }
}
