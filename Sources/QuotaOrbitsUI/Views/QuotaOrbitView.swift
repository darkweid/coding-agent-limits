import QuotaOrbitsCore
import SwiftUI

@_spi(Testing)
public enum QuotaOrbitMetrics {
    public static let diameter: CGFloat = 55.2
}

struct QuotaOrbitView: View {
    let window: String
    let countdown: String
    let usedPercent: Double?
    let dataState: QuotaBarDataState
    let displayMode: QuotaDisplayMode

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.09), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: QuotaBarMetrics.normalized(displayPercent) / 100)
                    .stroke(
                        levelColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(QuotaCopy.percent(displayPercent))
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(levelColor)
            }
            .frame(width: QuotaOrbitMetrics.diameter, height: QuotaOrbitMetrics.diameter)

            Text(window)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.74))
                .lineLimit(1)
            Text(countdown)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quota \(QuotaDisplayValue.label(for: displayMode))")
        .accessibilityValue(
            QuotaBarAccessibility.value(
                window: window,
                used: usedPercent,
                countdown: countdown,
                dataState: dataState,
                displayMode: displayMode
            )
        )
    }

    private var displayPercent: Double? {
        QuotaDisplayValue.percent(usedPercent: usedPercent, mode: displayMode)
    }

    private var levelColor: Color {
        QuotaPalette.color(for: QuotaLevel.classify(usedPercent: usedPercent))
    }
}
