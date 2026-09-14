import AppKit
import SwiftUI
@_spi(Testing) import QuotaOrbitsUI

enum SettingsWindowControllerTests {
    static let cases: [TestCase] = [
        TestCase(name: "SettingsWindowControllerTests.testPresentShowsAndReusesKeyCapableWindow") {
            try await MainActor.run {
                _ = NSApplication.shared
                let controller = SettingsWindowController(
                    rootView: Text("Settings fixture")
                )
                guard let originalWindow = controller.window else {
                    throw AssertionFailure(message: "Expected a settings window")
                }

                try TestSupport.assertFalse(originalWindow.isVisible)
                try TestSupport.assertTrue(originalWindow.canBecomeKey)

                controller.present()
                try TestSupport.assertTrue(originalWindow.isVisible)

                controller.present()
                try TestSupport.assertTrue(controller.window === originalWindow)

                controller.close()
            }
        },
        TestCase(name: "SettingsWindowControllerTests.testPresentCentersOnRequestedScreen") {
            try await MainActor.run {
                _ = NSApplication.shared
                let controller = SettingsWindowController(
                    rootView: Text("Settings fixture")
                )
                let secondaryScreen = CGRect(x: 1_920, y: 100, width: 1_440, height: 900)

                controller.present(on: secondaryScreen)

                guard let frame = controller.window?.frame else {
                    throw AssertionFailure(message: "Expected a settings window")
                }
                try TestSupport.assertEqual(frame.midX, secondaryScreen.midX)
                try TestSupport.assertEqual(frame.midY, secondaryScreen.midY)
                try TestSupport.assertTrue(secondaryScreen.contains(frame))
                controller.close()
            }
        },
    ]
}
