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
        }
    ]
}
