import Foundation
import QuotaOrbitsCore

enum QuotaModelsTests {
    static let cases: [TestCase] = [
        TestCase(name: "QuotaModelsTests.testRemainingPercentIsHundredMinusUsed") {
            let window = QuotaWindow(
                usedPercent: 72,
                resetsAt: Date(timeIntervalSince1970: 2_000)
            )
            try TestSupport.assertEqual(window.remainingPercent, 28)
        },
        TestCase(name: "QuotaModelsTests.testRemainingPercentIsClamped") {
            try TestSupport.assertEqual(
                QuotaWindow(usedPercent: -5, resetsAt: .distantFuture).remainingPercent,
                100
            )
            try TestSupport.assertEqual(
                QuotaWindow(usedPercent: 140, resetsAt: .distantFuture).remainingPercent,
                0
            )
        },
        TestCase(name: "QuotaModelsTests.testQuotaLevelBoundaries") {
            try TestSupport.assertEqual(
                QuotaLevel.classify(remainingPercent: 19),
                .critical
            )
            try TestSupport.assertEqual(QuotaLevel.classify(remainingPercent: 20), .low)
            try TestSupport.assertEqual(QuotaLevel.classify(remainingPercent: 50), .low)
            try TestSupport.assertEqual(
                QuotaLevel.classify(remainingPercent: 51),
                .healthy
            )
        }
    ]
}
