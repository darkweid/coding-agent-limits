import SwiftUI

struct ProviderActiveIndicator: View {
    let provider: ProviderHeaderLayout.Provider
    let isActive: Bool

    var body: some View {
        if ProviderHeaderLayout.activeIndicatorPlacement(for: provider) == .trailing {
            Spacer(minLength: 2)
        }
        if isActive {
            Circle()
                .fill(QuotaPalette.color(for: .healthy))
                .frame(width: 6, height: 6)
                .accessibilityLabel("Active account")
        }
    }
}
