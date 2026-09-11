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

@_spi(Testing)
@MainActor
public protocol PanelScreenChangeScheduling: AnyObject {
    func schedule(_ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
private final class DelayedPanelScreenChangeScheduler: PanelScreenChangeScheduling {
    private var task: Task<Void, Never>?

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
public final class DesktopPanelController: NSObject, NSWindowDelegate {
    public static let panelSize = CGSize(width: 350, height: 372)

    private let preferences: PanelPreferences
    private let actions: DashboardActions
    private let panel: NSPanel
    private let screenFrames: @MainActor () -> [CGRect]
    private let screenChangeScheduler: any PanelScreenChangeScheduling
    private var screenObservation: ScreenObservation?
    private var preferredOrigin: CGPoint
    private var isScreenConfigurationChanging = false
    private var isClosed = false

    public convenience init(
        coordinator: QuotaRefreshCoordinator,
        actions: DashboardActions,
        preferences: PanelPreferences
    ) {
        self.init(
            coordinator: coordinator,
            actions: actions,
            preferences: preferences,
            screenFrames: { NSScreen.screens.map(\.visibleFrame) },
            notificationCenter: .default,
            screenChangeScheduler: DelayedPanelScreenChangeScheduler()
        )
    }

    @_spi(Testing)
    public init(
        coordinator: QuotaRefreshCoordinator,
        actions: DashboardActions,
        preferences: PanelPreferences,
        screenFrames: @escaping @MainActor () -> [CGRect],
        notificationCenter: NotificationCenter,
        screenChangeScheduler: any PanelScreenChangeScheduling
    ) {
        self.preferences = preferences
        self.actions = actions
        self.screenFrames = screenFrames
        self.screenChangeScheduler = screenChangeScheduler

        let size = Self.panelSize
        let screens = screenFrames()
        let fallbackFrame =
            NSScreen.main?.visibleFrame
            ?? screens.first
            ?? CGRect(origin: .zero, size: size)
        let fallbackOrigin = CGPoint(
            x: fallbackFrame.maxX - size.width - 24,
            y: fallbackFrame.maxY - size.height - 24
        )
        let preferredOrigin = preferences.panelOrigin ?? fallbackOrigin
        let origin = PanelPlacement.clampedOrigin(
            preferredOrigin,
            panelSize: size,
            screenFrames: screens
        )

        let panel = DesktopPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.preferredOrigin = preferredOrigin
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
                actions: actions
            )
        )

        applyPinnedState(preferences.isPinned, persistOrigin: false)
        if preferences.panelOrigin == nil {
            preferences.panelOrigin = origin
        }

        let token = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                self.isScreenConfigurationChanging = true
                self.screenChangeScheduler.schedule { [weak self] in
                    self?.restorePreferredOriginToCurrentScreens()
                }
            }
        }
        screenObservation = ScreenObservation(center: notificationCenter, token: token)
    }

    public func show() {
        panel.orderFrontRegardless()
        restorePreferredOriginToCurrentScreens()
        DispatchQueue.main.async { [weak self] in
            self?.restorePreferredOriginToCurrentScreens()
        }
    }

    public func togglePinned() {
        applyPinnedState(!preferences.isPinned, persistOrigin: true)
    }

    public func persistOrigin() {
        guard !preferences.isPinned, !isScreenConfigurationChanging else { return }
        preferredOrigin = panel.frame.origin
        preferences.panelOrigin = preferredOrigin
    }

    public func close() {
        guard !isClosed else { return }
        persistOrigin()
        isClosed = true
        screenChangeScheduler.cancel()
        screenObservation?.invalidate()
        screenObservation = nil
        panel.orderOut(nil)
        panel.close()
    }

    public func windowDidMove(_ notification: Notification) {
        persistOrigin()
    }

    @_spi(Testing)
    public var panelFrameForTesting: CGRect {
        panel.frame
    }

    @_spi(Testing)
    public func setPanelFrameForTesting(_ frame: CGRect) {
        panel.setFrame(frame, display: false)
    }

    private func applyPinnedState(
        _ isPinned: Bool,
        persistOrigin: Bool
    ) {
        if persistOrigin {
            self.persistOrigin()
        }
        preferences.isPinned = isPinned
        actions.isPinned = isPinned
        panel.isMovableByWindowBackground = !isPinned
        panel.level = isPinned ? PanelWindowLevel.currentPinned : .floating
    }

    private func restorePreferredOriginToCurrentScreens() {
        let origin = PanelPlacement.clampedOrigin(
            preferredOrigin,
            panelSize: panel.frame.size,
            screenFrames: screenFrames()
        )
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
        isScreenConfigurationChanging = false
    }
}
