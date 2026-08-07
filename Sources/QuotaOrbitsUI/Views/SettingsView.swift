import SwiftUI

public struct SettingsView: View {
    @Binding private var cswapPath: String
    @Binding private var codexPath: String
    @Binding private var launchAtLogin: Bool

    public init(
        cswapPath: Binding<String>,
        codexPath: Binding<String>,
        launchAtLogin: Binding<Bool>
    ) {
        _cswapPath = cswapPath
        _codexPath = codexPath
        _launchAtLogin = launchAtLogin
    }

    public var body: some View {
        Form {
            Section("Источники") {
                TextField("Путь 1", text: $cswapPath)
                    .textFieldStyle(.roundedBorder)
                TextField("Путь 2", text: $codexPath)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Система") {
                Toggle("Запускать при входе", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 430, height: 230)
    }
}
