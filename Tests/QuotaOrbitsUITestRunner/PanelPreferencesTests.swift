import AppKit
import Foundation
@_spi(Testing) import QuotaOrbitsUI

enum PanelPreferencesTests {
    static let cases: [TestCase] = [
        TestCase(name: "PanelPreferencesTests.testDefaultPathsMatchApprovedExecutables") {
            try await withPreferences { preferences, _ in
                try TestSupport.assertEqual(
                    preferences.cswapPath,
                    "/Users/example/.local/bin/cswap"
                )
                try TestSupport.assertEqual(
                    preferences.codexPath,
                    "/opt/homebrew/bin/codex"
                )
            }
        },
        TestCase(name: "PanelPreferencesTests.testPanelOriginAndPinnedStateRoundTrip") {
            try await withPreferences { preferences, defaults in
                preferences.panelOrigin = CGPoint(x: 120, y: 240)
                preferences.isPinned = false

                let restored = PanelPreferences(defaults: defaults)
                try TestSupport.assertEqual(
                    restored.panelOrigin,
                    CGPoint(x: 120, y: 240)
                )
                try TestSupport.assertFalse(restored.isPinned)
            }
        },
        TestCase(name: "PanelPreferencesTests.testExecutablePathsRoundTripUnderStableKeys") {
            try await withPreferences { preferences, defaults in
                preferences.cswapPath = "/approved/cswap"
                preferences.codexPath = "/approved/codex"

                let restored = PanelPreferences(defaults: defaults)
                try TestSupport.assertEqual(restored.cswapPath, "/approved/cswap")
                try TestSupport.assertEqual(restored.codexPath, "/approved/codex")

                let persistedKeys = Set(
                    defaults.dictionaryRepresentation().keys.filter {
                        $0.hasPrefix("quotaOrbits.")
                    }
                )
                try TestSupport.assertEqual(
                    persistedKeys,
                    Set([
                        "quotaOrbits.cswapPath",
                        "quotaOrbits.codexPath"
                    ])
                )
            }
        },
        TestCase(name: "PanelPreferencesTests.testOnlyApprovedPreferenceKeysArePersisted") {
            try await withPreferences { preferences, defaults in
                preferences.cswapPath = "/approved/cswap"
                preferences.codexPath = "/approved/codex"
                preferences.panelOrigin = CGPoint(x: 20, y: 40)
                preferences.isPinned = false

                let persistedKeys = Set(
                    defaults.dictionaryRepresentation().keys.filter {
                        $0.hasPrefix("quotaOrbits.")
                    }
                )
                try TestSupport.assertEqual(
                    persistedKeys,
                    Set([
                        "quotaOrbits.cswapPath",
                        "quotaOrbits.codexPath",
                        "quotaOrbits.panelOrigin.x",
                        "quotaOrbits.panelOrigin.y",
                        "quotaOrbits.isPinned"
                    ])
                )
            }
        },
        TestCase(name: "PanelPreferencesTests.testRestoredOriginClampsToCurrentScreenBounds") {
            let result = PanelPlacement.clampedOrigin(
                CGPoint(x: 9_000, y: -4_000),
                panelSize: CGSize(width: 350, height: 350),
                screenFrames: [CGRect(x: 0, y: 0, width: 1_440, height: 900)]
            )

            try TestSupport.assertEqual(result, CGPoint(x: 1_090, y: 0))
        },
        TestCase(name: "PanelPreferencesTests.testClampingChoosesARealScreenInsteadOfDisplayGap") {
            let result = PanelPlacement.clampedOrigin(
                CGPoint(x: 1_700, y: 700),
                panelSize: CGSize(width: 350, height: 350),
                screenFrames: [
                    CGRect(x: 0, y: 0, width: 1_440, height: 900),
                    CGRect(x: 1_920, y: 0, width: 1_080, height: 1_920)
                ]
            )

            try TestSupport.assertEqual(result, CGPoint(x: 1_920, y: 700))
        }
    ]

    @MainActor
    private static func withPreferences(
        _ body: @MainActor (PanelPreferences, UserDefaults) throws -> Void
    ) async throws {
        let suiteName = "QuotaOrbitsUITests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw AssertionFailure(message: "Could not create isolated UserDefaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(PanelPreferences(defaults: defaults), defaults)
    }
}
