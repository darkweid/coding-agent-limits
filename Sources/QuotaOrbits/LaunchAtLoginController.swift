import Combine
import QuotaOrbitsUI
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) -> LaunchAtLoginNotice {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = SMAppService.mainApp.status == .enabled
            return .updated
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
            return .updateFailed
        }
    }
}
