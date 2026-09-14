import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    public init<Content: View>(rootView: Content) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 430, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public func present(on screenFrame: CGRect? = nil) {
        if let screenFrame, let window {
            window.contentView?.layoutSubtreeIfNeeded()
            let origin = CGPoint(
                x: screenFrame.midX - window.frame.width / 2,
                y: screenFrame.midY - window.frame.height / 2
            )
            window.setFrameOrigin(
                PanelPlacement.clampedOrigin(
                    origin,
                    panelSize: window.frame.size,
                    screenFrames: [screenFrame]
                )
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
