import SwiftUI

struct QuotaGaugeView: View {
    let window: String
    let countdown: String
    let usedPercent: Double?
    let dataState: QuotaBarDataState
    let displayMode: QuotaDisplayMode
    let visualStyle: QuotaVisualStyle

    @ViewBuilder
    var body: some View {
        switch visualStyle {
        case .bars:
            QuotaBarView(
                window: window,
                countdown: countdown,
                usedPercent: usedPercent,
                dataState: dataState,
                displayMode: displayMode
            )
        case .orbits:
            QuotaOrbitView(
                window: window,
                countdown: countdown,
                usedPercent: usedPercent,
                dataState: dataState,
                displayMode: displayMode
            )
        }
    }
}
