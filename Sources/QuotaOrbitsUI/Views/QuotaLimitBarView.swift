import SwiftUI

@_spi(Testing)
public enum QuotaLimitBarMetrics {
    public static func normalized(_ percent: Double) -> Double {
        min(max(percent, 0), 100)
    }
}

struct QuotaLimitBarView: View {
    let limit: QuotaLimitPresentation
    let status: PresentationStatus
    let now: Date

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Text(limit.label)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white.opacity(0.74))
                Text("· \(QuotaCopy.resetCountdown(resetsAt: limit.resetsAt, now: now))")
                    .foregroundStyle(Color.white.opacity(0.36))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 4)
                Text(QuotaCopy.percent(limit.displayPercent))
                    .fontWeight(.semibold)
                    .foregroundStyle(levelColor)
            }
            .font(.system(size: 10, design: .rounded))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(levelColor)
                        .frame(
                            width: geometry.size.width
                                * QuotaLimitBarMetrics.normalized(limit.displayPercent) / 100
                        )
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(limit.label)
        .accessibilityValue(accessibilityValue)
    }

    private var levelColor: Color { QuotaPalette.color(for: limit.level) }

    private var accessibilityValue: String {
        let mode = limit.displayMode == .used ? "used" : "remaining"
        let reset = QuotaCopy.resetCountdown(resetsAt: limit.resetsAt, now: now)
        let state = status.text(now: now).map { ", \($0)" } ?? ""
        return "\(QuotaCopy.percent(limit.displayPercent)) \(mode), \(reset)\(state)"
    }
}
