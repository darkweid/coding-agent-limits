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
        TestCase(name: "ClaudeUsageTerminalParserTests.testStripsClaudeTerminalControls") {
            let transcript = Data(
                """
                \u{1B}]0;Claude Code\u{7}\u{1B}(B\u{F}\u{1B}[32mCurrent session\u{1B}[0m
                21% used
                Resets 6:20pm (Asia/Tashkent)
                Current week (all models)
                2% used
                Resets Sep 21 at 3am (Asia/Tashkent)
                Esc to cancel
                """.utf8
            )

            let usage = try ClaudeUsageTerminalParser().parse(
                transcript,
                now: Date(timeIntervalSince1970: 1_789_467_600)
            )

            try TestSupport.assertEqual(usage.fiveHour?.usedPercent, 21)
            try TestSupport.assertEqual(usage.weekly?.usedPercent, 2)
        },
        TestCase(name: "ClaudeUsageTerminalParserTests.testRejectsUnknownOSCCommand") {
            let transcript = Data(
                """
                \u{1B}]52;c;clipboard-payload\u{7}
                Current session
                21% used
                Resets 6:20pm (Asia/Tashkent)
                Current week (all models)
                2% used
                Resets Sep 21 at 3am (Asia/Tashkent)
                """.utf8
            )

            try await TestSupport.assertThrowsErrorAsync(
                try ClaudeUsageTerminalParser().parse(
                    transcript,
                    now: Date(timeIntervalSince1970: 1_789_467_600)
                )
            ) { error in
                try TestSupport.assertEqual(
                    error as? ClaudeUsageTerminalParseError,
                    .invalidResponse
                )
            }
        },
        TestCase(name: "ClaudeUsageTerminalParserTests.testRestoresCursorPositionedSpacing") {
            let transcript = Data(
                """
                Current\u{1B}[12Gsession
                21%\u{1B}[59Gused
                Resets\u{1B}[11G6pm\u{1B}[18G(Asia/Tashkent)
                Current\u{1B}[12Gweek\u{1B}[17G(all\u{1B}[22Gmodels)
                2%\u{1B}[58Gused
                Resets\u{1B}[11GSep\u{1B}[15G21\u{1B}[18Gat\u{1B}[21G3am\u{1B}[25G(Asia/Tashkent)
                Esc\u{1B}[8Gto\u{1B}[11Gcancel
                """.utf8
            )

            let usage = try ClaudeUsageTerminalParser().parse(
                transcript,
                now: Date(timeIntervalSince1970: 1_789_467_600)
            )

            try TestSupport.assertEqual(usage.fiveHour?.usedPercent, 21)
            try TestSupport.assertEqual(usage.weekly?.usedPercent, 2)
            try TestSupport.assertEqual(usage.fiveHour?.resetsAt != nil, true)
            try TestSupport.assertEqual(usage.weekly?.resetsAt != nil, true)
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
