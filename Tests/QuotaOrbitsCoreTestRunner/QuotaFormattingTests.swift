import Foundation
import QuotaOrbitsCore

enum QuotaFormattingTests {
    static let cases: [TestCase] = [
        TestCase(name: "QuotaFormattingTests.testMinutesOnly") {
            let now = Date(timeIntervalSince1970: 1_000_000)
            try TestSupport.assertEqual(
                ResetCountdownFormatter.string(
                    until: now.addingTimeInterval(25 * 60),
                    now: now
                ),
                "resets in 25m"
            )
        },
        TestCase(name: "QuotaFormattingTests.testHoursAndMinutes") {
            let now = Date(timeIntervalSince1970: 1_000_000)
            try TestSupport.assertEqual(
                ResetCountdownFormatter.string(
                    until: now.addingTimeInterval((3 * 60 + 25) * 60),
                    now: now
                ),
                "resets in 3h 25m"
            )
        },
        TestCase(name: "QuotaFormattingTests.testDaysAndHoursDropsMinutes") {
            let now = Date(timeIntervalSince1970: 1_000_000)
            try TestSupport.assertEqual(
                ResetCountdownFormatter.string(
                    until: now.addingTimeInterval((2 * 24 + 13) * 3_600),
                    now: now
                ),
                "resets in 2d 13h"
            )
        },
        TestCase(name: "QuotaFormattingTests.testExpiredWindow") {
            let now = Date(timeIntervalSince1970: 1_000_000)
            try TestSupport.assertEqual(
                ResetCountdownFormatter.string(until: now, now: now),
                "resets now"
            )
        },
    ]
}
