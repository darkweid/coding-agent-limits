import SwiftUI

@main
struct QuotaOrbitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            appDelegate.settingsView
        }
    }
}
