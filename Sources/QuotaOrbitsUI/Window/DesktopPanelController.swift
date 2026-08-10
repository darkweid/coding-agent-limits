import AppKit
import QuotaOrbitsCore
import SwiftUI

private final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@_spi(Testing)
public enum PanelWindowLevel {
    public static func pinned(
        desktopIconLevel: Int,
        normalLevel: Int
    ) -> NSWindow.Level {
        NSWindow.Level(
            rawValue: min(desktopIconLevel + 1, normalLevel - 1)
        )
    }

    static var currentPinned: NSWindow.Level {
        pinned(
            desktopIconLevel: Int(CGWindowLevelForKey(.desktopIconWindow)),
            normalLevel: NSWindow.Level.normal.rawValue
        )
    }
}

private final class ScreenObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    func invalidate() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit {
        invalidate()
    }
}

@MainActor
public final class DesktopPanelController: NSObject, NSWindowDelegate {
    public static let panelSize = CGSize(width: 350, height: 350)

    private let preferences: AppPreferences
    private let actions: DashboardActions
    private let panel: NSPanel
    private var screenObservation: ScreenObservation?

    public init(
        coordinator: QuotaFeedRefreshCoordinator,
        actions: DashboardActions,
        preferences: AppPreferences
    ) {
        self.preferences = preferences
        self.actions = actions

        let size = Self.panelSize
        let screens = NSScreen.screens.map(\.visibleFrame)
        let fallbackFrame =
            NSScreen.main?.visibleFrame
            ?? screens.first
            ?? CGRect(origin: .zero, size: size)
        let fallbackOrigin = CGPoint(
            x: fallbackFrame.maxX - size.width - 24,
            y: fallbackFrame.maxY - size.height - 24
        )
        let origin = PanelPlacement.clampedOrigin(
            preferences.panelOrigin ?? fallbackOrigin,
            panelSize: size,
            screenFrames: screens
        )

        let panel = DesktopPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        super.init()

        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
        ]
        panel.contentViewController = NSHostingController(
            rootView: DashboardView(
                coordinator: coordinator,
                preferences: preferences,
                actions: actions
            )
        )

        applyPinnedState(preferences.isPinned, persistOrigin: false)
        preferences.panelOrigin = origin

        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clampToCurrentScreens()
            }
        }
        screenObservation = ScreenObservation(center: center, token: token)
    }

    public func show() {
        clampToCurrentScreens()
        panel.orderFrontRegardless()
    }

    public func togglePinned() {
        applyPinnedState(!preferences.isPinned, persistOrigin: true)
    }

    public func persistOrigin() {
        preferences.panelOrigin = panel.frame.origin
    }

    public func close() {
        persistOrigin()
        screenObservation?.invalidate()
        screenObservation = nil
        panel.orderOut(nil)
        panel.close()
    }

    public func windowDidMove(_ notification: Notification) {
        persistOrigin()
    }

    private func applyPinnedState(
        _ isPinned: Bool,
        persistOrigin: Bool
    ) {
        if persistOrigin {
            preferences.panelOrigin = panel.frame.origin
        }
        preferences.isPinned = isPinned
        actions.isPinned = isPinned
        panel.isMovableByWindowBackground = !isPinned
        panel.level = isPinned ? PanelWindowLevel.currentPinned : .floating
    }

    private func clampToCurrentScreens() {
        let origin = PanelPlacement.clampedOrigin(
            panel.frame.origin,
            panelSize: panel.frame.size,
            screenFrames: NSScreen.screens.map(\.visibleFrame)
        )
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
        preferences.panelOrigin = origin
    }
}
