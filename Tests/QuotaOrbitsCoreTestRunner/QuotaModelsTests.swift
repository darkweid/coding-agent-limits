import Foundation
import QuotaOrbitsCore

enum QuotaModelsTests {
    static let cases: [TestCase] = [
        TestCase(name: "QuotaModelsTests.testRemainingPercentIsHundredMinusUsed") {
            let window = QuotaWindow(
                usedPercent: 72,
                resetsAt: Date(timeIntervalSince1970: 2_000)
            )
            try TestSupport.assertEqual(window.usedPercent, 72)
            try TestSupport.assertEqual(window.remainingPercent, 28)
        },
        TestCase(name: "QuotaModelsTests.testUsedAndRemainingPercentAreClampedTogether") {
            try TestSupport.assertEqual(
                QuotaWindow(usedPercent: -5, resetsAt: .distantFuture).usedPercent,
                0
            )
            try TestSupport.assertEqual(
                QuotaWindow(usedPercent: -5, resetsAt: .distantFuture).remainingPercent,
                100
            )
            try TestSupport.assertEqual(
                QuotaWindow(usedPercent: 140, resetsAt: .distantFuture).usedPercent,
                100
            )
            try TestSupport.assertEqual(
                QuotaWindow(usedPercent: 140, resetsAt: .distantFuture).remainingPercent,
                0
            )
        },
        TestCase(name: "QuotaModelsTests.testUsedQuotaLevelBoundaries") {
            try TestSupport.assertEqual(
                QuotaLevel.classify(usedPercent: nil),
                .unavailable
            )
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 0), .healthy)
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 70), .healthy)
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 70.01), .warning)
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 85), .warning)
            try TestSupport.assertEqual(
                QuotaLevel.classify(usedPercent: 85.01),
                .critical
            )
            try TestSupport.assertEqual(QuotaLevel.classify(usedPercent: 100), .critical)
        }
    ]
}
