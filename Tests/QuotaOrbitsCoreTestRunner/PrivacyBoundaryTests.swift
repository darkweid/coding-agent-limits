import Foundation
@_spi(Testing) import QuotaOrbitsCore

enum PrivacyBoundaryTests {
    static let cases: [TestCase] = [
        TestCase(name: "PrivacyBoundaryTests.testLoggingSubsystemUsesNeutralIdentifier") {
            try TestSupport.assertEqual(
                SafeLogger.subsystem,
                "io.github.darkweid.coding-agent-limits"
            )
        }
    ]
}
