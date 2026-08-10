import QuotaOrbitsCore
@_spi(Testing) import QuotaOrbitsUI

enum QuotaPaletteTests {
    static let cases: [TestCase] = [
        TestCase(name: "QuotaPaletteTests.testApprovedThresholdsMapToDistinctSemanticColors") {
            try TestSupport.assertEqual(QuotaPalette.token(for: .healthy), .healthy)
            try TestSupport.assertEqual(QuotaPalette.token(for: .warning), .warning)
            try TestSupport.assertEqual(QuotaPalette.token(for: .critical), .critical)
            try TestSupport.assertEqual(QuotaPalette.token(for: .unavailable), .unavailable)
            try TestSupport.assertEqual(
                QuotaPalette.components(for: .warning),
                QuotaColorComponents(red: 0.91, green: 0.72, blue: 0.28)
            )
        }
    ]
}
