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
    private var settingsWindowController: SettingsWindowController?
    private var dashboardActions: DashboardActions?
    private var isTerminationPending = false
    private var didFinishShutdown = false

    var settingsView: some View {
        SettingsView(
            preferences: preferences,
            claudeSourceMode: Binding(
                get: { [weak self] in self?.preferences.claudeSourceMode ?? .cswap },
                set: { [weak self] in self?.setClaudeSourceMode($0) }
            ),
            cswapPath: Binding(
                get: { [weak self] in
                    self?.preferences.cswapPath
                        ?? PanelPreferences.defaultCswapPath
                },
                set: { [weak self] in self?.setCswapPath($0) }
            ),
            claudePath: Binding(
                get: { [weak self] in
                    self?.preferences.claudePath
                        ?? PanelPreferences.defaultClaudePath
                },
                set: { [weak self] in self?.setClaudePath($0) }
            ),
            codexPath: Binding(
                get: { [weak self] in
                    self?.preferences.codexPath
                        ?? PanelPreferences.defaultCodexPath
                },
                set: { [weak self] in self?.setCodexPath($0) }
            ),
            refreshIntervalSeconds: Binding(
                get: { [weak self] in self?.preferences.refreshIntervalSeconds ?? 60 },
                set: { [weak self] in self?.setRefreshInterval($0) }
            ),
            displayMode: Binding(
                get: { [weak self] in self?.preferences.displayMode ?? .used },
                set: { [weak self] in self?.preferences.displayMode = $0 }
            ),
            visualStyle: Binding(
                get: { [weak self] in self?.preferences.visualStyle ?? .bars },
                set: { [weak self] in self?.preferences.visualStyle = $0 }
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
            settingsWindowController?.close()
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

    private func setClaudePath(_ path: String) {
        if let runtime {
            runtime.updateClaudePath(path)
        } else {
            preferences.claudePath = path
        }
    }

    private func setClaudeSourceMode(_ mode: ClaudeSourceMode) {
        if let runtime {
            runtime.updateClaudeSourceMode(mode)
        } else {
            preferences.claudeSourceMode = mode
        }
    }

    private func setCodexPath(_ path: String) {
        if let runtime {
            runtime.updateCodexPath(path)
        } else {
            preferences.codexPath = path
        }
    }

    private func setRefreshInterval(_ seconds: Int) {
        preferences.refreshIntervalSeconds = seconds
        runtime?.updateRefreshInterval(seconds: preferences.refreshIntervalSeconds)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginNotice = launchAtLogin.setEnabled(enabled)
    }

    private func openSettings() {
        let controller: SettingsWindowController
        if let settingsWindowController {
            controller = settingsWindowController
        } else {
            controller = SettingsWindowController(rootView: settingsView)
            settingsWindowController = controller
        }
        controller.present(on: panelController?.currentScreenVisibleFrame)
    }
}
