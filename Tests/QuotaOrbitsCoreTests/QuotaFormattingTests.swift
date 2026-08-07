import XCTest
@testable import QuotaOrbitsCore

final class QuotaFormattingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testMinutesOnly() {
        XCTAssertEqual(
            ResetCountdownFormatter.string(
                until: now.addingTimeInterval(25 * 60),
                now: now
            ),
            "сброс через 25м"
        )
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(
            ResetCountdownFormatter.string(
                until: now.addingTimeInterval((3 * 60 + 25) * 60),
                now: now
            ),
            "сброс через 3ч 25м"
        )
    }

    func testDaysAndHoursDropsMinutes() {
        XCTAssertEqual(
            ResetCountdownFormatter.string(
                until: now.addingTimeInterval((2 * 24 + 13) * 3_600),
                now: now
            ),
            "сброс через 2д 13ч"
        )
    }

    func testExpiredWindow() {
        XCTAssertEqual(
            ResetCountdownFormatter.string(until: now, now: now),
            "сброс сейчас"
        )
    }
}
