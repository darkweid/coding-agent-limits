import Foundation
import QuotaOrbitsCore

enum QuotaFormattingTests {
    static let cases: [TestCase] = [
        TestCase(name: "QuotaFormattingTests.minutes only") {
            let now = Date(timeIntervalSince1970: 1_000_000)
            try TestSupport.assertEqual(
                ResetCountdownFormatter.string(
                    until: now.addingTimeInterval(25 * 60),
                    now: now
                ),
                "сброс через 25м"
            )
        },
        TestCase(name: "QuotaFormattingTests.hours and minutes") {
            let now = Date(timeIntervalSince1970: 1_000_000)
            try TestSupport.assertEqual(
                ResetCountdownFormatter.string(
                    until: now.addingTimeInterval((3 * 60 + 25) * 60),
                    now: now
                ),
                "сброс через 3ч 25м"
            )
        },
        TestCase(name: "QuotaFormattingTests.days and hours drops minutes") {
            let now = Date(timeIntervalSince1970: 1_000_000)
            try TestSupport.assertEqual(
                ResetCountdownFormatter.string(
                    until: now.addingTimeInterval((2 * 24 + 13) * 3_600),
                    now: now
                ),
                "сброс через 2д 13ч"
            )
        },
        TestCase(name: "QuotaFormattingTests.expired window") {
            let now = Date(timeIntervalSince1970: 1_000_000)
            try TestSupport.assertEqual(
                ResetCountdownFormatter.string(until: now, now: now),
                "сброс сейчас"
            )
        }
    ]
}
