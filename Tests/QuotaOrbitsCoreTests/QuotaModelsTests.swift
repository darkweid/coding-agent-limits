import XCTest
@testable import QuotaOrbitsCore

final class QuotaModelsTests: XCTestCase {
    func testRemainingPercentIsHundredMinusUsed() {
        let window = QuotaWindow(
            usedPercent: 72,
            resetsAt: Date(timeIntervalSince1970: 2_000)
        )
        XCTAssertEqual(window.remainingPercent, 28)
    }

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(
            QuotaWindow(usedPercent: -5, resetsAt: .distantFuture).remainingPercent,
            100
        )
        XCTAssertEqual(
            QuotaWindow(usedPercent: 140, resetsAt: .distantFuture).remainingPercent,
            0
        )
    }

    func testQuotaLevelBoundaries() {
        XCTAssertEqual(QuotaLevel.classify(remainingPercent: 19), .critical)
        XCTAssertEqual(QuotaLevel.classify(remainingPercent: 20), .low)
        XCTAssertEqual(QuotaLevel.classify(remainingPercent: 50), .low)
        XCTAssertEqual(QuotaLevel.classify(remainingPercent: 51), .healthy)
    }
}
