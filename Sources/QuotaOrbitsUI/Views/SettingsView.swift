import SwiftUI

public enum LaunchAtLoginNotice: Equatable, Sendable {
    case updated
    case updateFailed

    public var text: String {
        switch self {
        case .updated: "Setting saved"
        case .updateFailed: "Could not change setting"
        }
    }

    public var isFailure: Bool {
        self == .updateFailed
    }
}

public struct SettingsView: View {
    @Binding private var cswapPath: String
    @Binding private var codexPath: String
    @Binding private var launchAtLogin: Bool
    @Binding private var launchAtLoginNotice: LaunchAtLoginNotice?

    public init(
        cswapPath: Binding<String>,
        codexPath: Binding<String>,
        launchAtLogin: Binding<Bool>,
        launchAtLoginNotice: Binding<LaunchAtLoginNotice?> = .constant(nil)
    ) {
        _cswapPath = cswapPath
        _codexPath = codexPath
        _launchAtLogin = launchAtLogin
        _launchAtLoginNotice = launchAtLoginNotice
    }

    public var body: some View {
        Form {
            Section("Sources") {
                TextField("Path 1", text: $cswapPath)
                    .textFieldStyle(.roundedBorder)
                TextField("Path 2", text: $codexPath)
                    .textFieldStyle(.roundedBorder)
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                if let notice = launchAtLoginNotice {
                    Text(notice.text)
                        .font(.caption)
                        .foregroundStyle(
                            notice.isFailure
                                ? Color(red: 0.84, green: 0.43, blue: 0.40)
                                : Color.secondary
                        )
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 430, height: 250)
    }
}
