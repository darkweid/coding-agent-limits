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

    public var isFailure: Bool { self == .updateFailed }
}

@_spi(Testing)
public enum SettingsPresentation {
    public enum PathKind: Equatable, Sendable {
        case cswap
        case claudeCode
    }

    public static func pathKind(for mode: ClaudeSourceMode) -> PathKind {
        mode == .cswap ? .cswap : .claudeCode
    }

    public static func refreshLabel(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) min" : "\(minutes)m \(remainder)s"
    }
}

public struct SettingsView: View {
    @Binding private var claudeSourceMode: ClaudeSourceMode
    @Binding private var cswapPath: String
    @Binding private var claudePath: String
    @Binding private var codexPath: String
    @Binding private var refreshIntervalSeconds: Int
    @Binding private var displayMode: QuotaDisplayMode
    @Binding private var visualStyle: QuotaVisualStyle
    @Binding private var launchAtLogin: Bool
    @Binding private var launchAtLoginNotice: LaunchAtLoginNotice?

    public init(
        claudeSourceMode: Binding<ClaudeSourceMode>,
        cswapPath: Binding<String>,
        claudePath: Binding<String>,
        codexPath: Binding<String>,
        refreshIntervalSeconds: Binding<Int>,
        displayMode: Binding<QuotaDisplayMode>,
        visualStyle: Binding<QuotaVisualStyle>,
        launchAtLogin: Binding<Bool>,
        launchAtLoginNotice: Binding<LaunchAtLoginNotice?> = .constant(nil)
    ) {
        _claudeSourceMode = claudeSourceMode
        _cswapPath = cswapPath
        _claudePath = claudePath
        _codexPath = codexPath
        _refreshIntervalSeconds = refreshIntervalSeconds
        _displayMode = displayMode
        _visualStyle = visualStyle
        _launchAtLogin = launchAtLogin
        _launchAtLoginNotice = launchAtLoginNotice
    }

    public var body: some View {
        Form {
            Section("Sources") {
                Picker("Claude source", selection: $claudeSourceMode) {
                    Text("cswap").tag(ClaudeSourceMode.cswap)
                    Text("Native Claude Code").tag(ClaudeSourceMode.nativeClaudeCode)
                }
                .pickerStyle(.segmented)

                if SettingsPresentation.pathKind(for: claudeSourceMode) == .cswap {
                    TextField("cswap executable", text: $cswapPath)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("Claude executable", text: $claudePath)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Codex executable", text: $codexPath)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Display") {
                HStack {
                    Text("Refresh")
                    Slider(
                        value: Binding(
                            get: { Double(refreshIntervalSeconds) },
                            set: { refreshIntervalSeconds = Int($0.rounded()) }
                        ),
                        in: 30...600,
                        step: 30
                    )
                    Text(SettingsPresentation.refreshLabel(seconds: refreshIntervalSeconds))
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                }
                Picker("Percentage", selection: $displayMode) {
                    Text("Used").tag(QuotaDisplayMode.used)
                    Text("Remaining").tag(QuotaDisplayMode.remaining)
                }
                .pickerStyle(.segmented)
                Picker("Style", selection: $visualStyle) {
                    Text("Bars").tag(QuotaVisualStyle.bars)
                    Text("Orbits").tag(QuotaVisualStyle.orbits)
                }
                .pickerStyle(.segmented)
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
        .frame(width: 460, height: 420)
    }
}
