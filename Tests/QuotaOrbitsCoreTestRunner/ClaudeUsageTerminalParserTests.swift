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

            let limits = try ClaudeUsageTerminalParser().parse(
                transcript,
                now: Date(timeIntervalSince1970: 1_786_335_600)
            )

            try TestSupport.assertEqual(limits.map(\.label), ["5 hours", "Weekly", "Fable"])
            try TestSupport.assertEqual(limits.map(\.usedPercent), [9, 79, 12])
            try TestSupport.assertEqual(limits[2].resetsAt, limits[1].resetsAt)
        },
        TestCase(name: "ClaudeUsageTerminalParserTests.testStripsSafeANSISequences") {
            let transcript = Data(
                "\u{1B}[32mCurrent session\u{1B}[0m\n2% used\nResets 11:59pm (UTC)\n"
                    .appending(
                        "Current week (all models)\n3% used\nResets Aug 14 at 10:59am (UTC)\nEsc to exit"
                    )
                    .utf8
            )

            let limits = try ClaudeUsageTerminalParser().parse(
                transcript,
                now: Date(timeIntervalSince1970: 1_786_335_600)
            )

            try TestSupport.assertEqual(limits.map(\.usedPercent), [2, 3])
        },
        TestCase(name: "ClaudeUsageTerminalParserTests.testRejectsMissingRequiredRows") {
            let transcript = Data("Current session\n2% used\nEsc to exit".utf8)

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
