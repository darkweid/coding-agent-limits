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
                guard let targetScreen = NSScreen.screens.last else {
                    throw AssertionFailure(message: "Expected an available screen")
                }
                let screenFrame = targetScreen.visibleFrame

                controller.present(on: screenFrame)

                guard let frame = controller.window?.frame else {
                    throw AssertionFailure(message: "Expected a settings window")
                }
                try TestSupport.assertTrue(abs(frame.midX - screenFrame.midX) <= 1)
                try TestSupport.assertTrue(abs(frame.midY - screenFrame.midY) <= 1)
                try TestSupport.assertTrue(screenFrame.contains(frame))
                controller.close()
            }
        },
    ]
}
