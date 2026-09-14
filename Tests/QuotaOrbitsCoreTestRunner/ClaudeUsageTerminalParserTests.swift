import Foundation
import QuotaOrbitsCore

enum ClaudeUsageTerminalParserTests {
    static let cases: [TestCase] = [
        TestCase(name: "ClaudeUsageTerminalParserTests.testParsesBaseAndScopedUsageRows") {
            let transcript = Data(
                """
                Settings: Status Config Usage (tab to cycle)

                Current session
                ███ 9% used
                Resets 11:59pm (America/New_York)

                Current week (all models)
                █████ 79% used
                Resets Aug 14 at 10:59am (America/New_York)

                Current week (Fable)
                ██ 12% used

                Esc to exit
                """.utf8)

            let usage = try ClaudeUsageTerminalParser().parse(
                transcript,
                now: Date(timeIntervalSince1970: 1_786_335_600)
            )

            try TestSupport.assertEqual(usage.fiveHour?.usedPercent, 9)
            try TestSupport.assertEqual(usage.weekly?.usedPercent, 79)
            try TestSupport.assertEqual(usage.scoped.map(\.label), ["Fable"])
            try TestSupport.assertEqual(usage.scoped.map(\.window.usedPercent), [12])
            try TestSupport.assertEqual(usage.scoped[0].window.resetsAt, usage.weekly?.resetsAt)
        },
        TestCase(name: "ClaudeUsageTerminalParserTests.testAcceptsOneAvailableBaseWindow") {
            let transcript = Data(
                "Current session\n2% used\nResets 11:59pm (UTC)\nEsc to exit".utf8
            )

            let usage = try ClaudeUsageTerminalParser().parse(
                transcript,
                now: Date(timeIntervalSince1970: 1_786_335_600)
            )

            try TestSupport.assertEqual(usage.fiveHour?.usedPercent, 2)
            try TestSupport.assertEqual(usage.weekly, nil)
        },
        TestCase(name: "ClaudeUsageTerminalParserTests.testStripsSafeANSISequences") {
            let transcript = Data(
                "\u{1B}[32mCurrent session\u{1B}[0m\n2% used\nResets 11:59pm (UTC)\nEsc to exit"
                    .utf8
            )

            let usage = try ClaudeUsageTerminalParser().parse(
                transcript,
                now: Date(timeIntervalSince1970: 1_786_335_600)
            )

            try TestSupport.assertEqual(usage.fiveHour?.usedPercent, 2)
        },
        TestCase(name: "ClaudeUsageTerminalParserTests.testRejectsTranscriptWithoutUsage") {
            let transcript = Data("Settings: Status Config Usage\nEsc to exit".utf8)

            try await TestSupport.assertThrowsErrorAsync(
                try ClaudeUsageTerminalParser().parse(transcript, now: .distantPast)
            ) { error in
                try TestSupport.assertEqual(
                    error as? ClaudeUsageTerminalParseError,
                    .invalidResponse
                )
            }
        },
        TestCase(name: "ClaudeUsageTerminalParserTests.testRejectsOversizedTranscript") {
            let transcript = Data(repeating: 0x78, count: 65_537)

            try await TestSupport.assertThrowsErrorAsync(
                try ClaudeUsageTerminalParser().parse(transcript, now: .distantPast)
            ) { error in
                try TestSupport.assertEqual(
                    error as? ClaudeUsageTerminalParseError,
                    .outputTooLarge
                )
            }
        },
    ]
}
