import AppKit
import QuotaOrbitsUI
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let preferences = PanelPreferences()
    let launchAtLogin = LaunchAtLoginController()
    @Published private var launchAtLoginNotice: LaunchAtLoginNotice?

    private var runtime: AppRuntime?
    private var panelController: DesktopPanelController?
    private var dashboardActions: DashboardActions?
    private var isTerminationPending = false
    private var didFinishShutdown = false

    var settingsView: some View {
        SettingsView(
            cswapPath: Binding(
                get: { [weak self] in
                    self?.preferences.cswapPath
                        ?? PanelPreferences.defaultCswapPath
                },
                set: { [weak self] in self?.setCswapPath($0) }
            ),
            codexPath: Binding(
                get: { [weak self] in
                    self?.preferences.codexPath
                        ?? PanelPreferences.defaultCodexPath
                },
                set: { [weak self] in self?.setCodexPath($0) }
            ),
            launchAtLogin: Binding(
                get: { [weak self] in self?.launchAtLogin.isEnabled ?? false },
                set: { [weak self] in self?.setLaunchAtLogin($0) }
            ),
            launchAtLoginNotice: Binding(
                get: { [weak self] in self?.launchAtLoginNotice },
                set: { [weak self] in self?.launchAtLoginNotice = $0 }
            )
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let runtime = AppRuntime(preferences: preferences)
        let actions = DashboardActions(
            isPinned: preferences.isPinned,
            refreshNow: { [weak self] in
                self?.runtime?.requestRefresh()
            },
            togglePinned: { [weak self] in
                self?.panelController?.togglePinned()
            },
            openSettings: { [weak self] in
                self?.openSettings()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
        let panelController = DesktopPanelController(
            coordinator: runtime.coordinator,
            actions: actions,
            preferences: preferences
        )

        self.runtime = runtime
        dashboardActions = actions
        self.panelController = panelController
        panelController.show()
        runtime.start()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if didFinishShutdown || runtime == nil {
            return .terminateNow
        }
        guard !isTerminationPending else { return .terminateLater }
        isTerminationPending = true
        panelController?.persistOrigin()

        Task { [weak self] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: true)
                return
            }
            await runtime?.shutdown()
            panelController?.close()
            didFinishShutdown = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func setCswapPath(_ path: String) {
        if let runtime {
            runtime.updateCswapPath(path)
        } else {
            preferences.cswapPath = path
        }
    }

    private func setCodexPath(_ path: String) {
        if let runtime {
            runtime.updateCodexPath(path)
        } else {
            preferences.codexPath = path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginNotice = launchAtLogin.setEnabled(enabled)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
    }
}
