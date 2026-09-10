import AppKit
import Foundation
import QuotaOrbitsCore
@_spi(Testing) import QuotaOrbitsUI

enum PanelPreferencesTests {
    static let cases: [TestCase] = [
        TestCase(name: "PanelPreferencesTests.testCswapDefaultUsesProvidedHomeDirectory") {
            let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

            let result = ExecutablePathResolver.defaultCswapPath(homeDirectory: home)

            try TestSupport.assertEqual(result, "/Users/example/.local/bin/cswap")
        },
        TestCase(name: "PanelPreferencesTests.testCodexDefaultPrefersFirstExecutableCandidate") {
            let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
            let executablePaths = Set([
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
            ])

            let result = ExecutablePathResolver.defaultCodexPath(
                homeDirectory: home,
                isExecutable: { executablePaths.contains($0) }
            )

            try TestSupport.assertEqual(result, "/opt/homebrew/bin/codex")
        },
        TestCase(name: "PanelPreferencesTests.testCodexDefaultPrefersUserLocalCandidate") {
            let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

            let result = ExecutablePathResolver.defaultCodexPath(
                homeDirectory: home,
                isExecutable: { $0 == "/Users/example/.local/bin/codex" }
            )

            try TestSupport.assertEqual(result, "/Users/example/.local/bin/codex")
        },
        TestCase(name: "PanelPreferencesTests.testCodexDefaultFallsBackToUserLocalCandidate") {
            let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

            let result = ExecutablePathResolver.defaultCodexPath(
                homeDirectory: home,
                isExecutable: { _ in false }
            )

            try TestSupport.assertEqual(result, "/Users/example/.local/bin/codex")
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
                        "quotaOrbits.codexPath",
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
                        "quotaOrbits.isPinned",
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
                    CGRect(x: 1_920, y: 0, width: 1_080, height: 1_920),
                ]
            )

            try TestSupport.assertEqual(result, CGPoint(x: 1_920, y: 700))
        },
        TestCase(name: "PanelPreferencesTests.testShowRecoversFromDeferredSystemRelocation") {
            try await withAsyncPreferences { preferences, _ in
                let screens = NSScreen.screens.map(\.visibleFrame)
                guard
                    let screen = screens.first,
                    let maxScreenX = screens.map(\.maxX).max()
                else {
                    throw AssertionFailure(message: "Expected at least one screen")
                }
                let injectedFrame = CGRect(
                    x: maxScreenX + DesktopPanelController.panelSize.width,
                    y: screen.midY,
                    width: DesktopPanelController.panelSize.width,
                    height: DesktopPanelController.panelSize.height
                )
                try TestSupport.assertFalse(
                    screens.contains(where: { $0.contains(injectedFrame) })
                )
                let controller = DesktopPanelController(
                    coordinator: QuotaRefreshCoordinator(
                        claude: UnusedClaudeQuotaSource(),
                        codex: UnusedCodexQuotaSource()
                    ),
                    actions: DashboardActions(
                        isPinned: true,
                        refreshNow: {},
                        togglePinned: {},
                        openSettings: {},
                        quit: {}
                    ),
                    preferences: preferences
                )
                defer { controller.close() }

                DispatchQueue.main.async {
                    controller.setPanelFrameForTesting(injectedFrame)
                }
                controller.show()
                await waitForMainQueue()

                let finalFrame = controller.panelFrameForTesting
                try TestSupport.assertTrue(
                    screens.contains(where: { $0.contains(finalFrame) })
                )
                try TestSupport.assertEqual(
                    preferences.panelOrigin,
                    finalFrame.origin
                )
            }
        },
        TestCase(name: "PanelWindowLevelTests.testPinnedPanelSitsAboveDesktopIconsAndBelowApps") {
            let desktopIcons = -20
            let normalWindows = 0

            let pinned = PanelWindowLevel.pinned(
                desktopIconLevel: desktopIcons,
                normalLevel: normalWindows
            )

            try TestSupport.assertEqual(pinned.rawValue, -19)
            try TestSupport.assertTrue(pinned.rawValue > desktopIcons)
            try TestSupport.assertTrue(pinned.rawValue < normalWindows)
        },
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

    @MainActor
    private static func withAsyncPreferences(
        _ body: @MainActor (PanelPreferences, UserDefaults) async throws -> Void
    ) async throws {
        let suiteName = "QuotaOrbitsUITests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw AssertionFailure(message: "Could not create isolated UserDefaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try await body(PanelPreferences(defaults: defaults), defaults)
    }

    @MainActor
    private static func waitForMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

private struct UnusedClaudeQuotaSource: ClaudeQuotaFetching {
    func fetch() async throws -> [ClaudeAccountQuota] {
        throw UnusedQuotaSourceError()
    }
}

private struct UnusedCodexQuotaSource: CodexQuotaFetching {
    func fetch() async throws -> CodexQuota {
        throw UnusedQuotaSourceError()
    }
}

private struct UnusedQuotaSourceError: Error {}
