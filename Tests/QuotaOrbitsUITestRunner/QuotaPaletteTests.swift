import QuotaOrbitsCore
@_spi(Testing) import QuotaOrbitsUI

enum QuotaPaletteTests {
    static let cases: [TestCase] = [
        TestCase(name: "QuotaPaletteTests.testApprovedThresholdsMapToDistinctSemanticColors") {
            try TestSupport.assertEqual(QuotaPalette.token(for: .healthy), .healthy)
            try TestSupport.assertEqual(QuotaPalette.token(for: .low), .low)
            try TestSupport.assertEqual(QuotaPalette.token(for: .critical), .critical)
            try TestSupport.assertEqual(QuotaPalette.token(for: .unavailable), .unavailable)
        }
    ]
}
