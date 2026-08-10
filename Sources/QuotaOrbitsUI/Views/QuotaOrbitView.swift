import SwiftUI

struct QuotaOrbitView: View {
    let limit: QuotaLimitPresentation
    let status: PresentationStatus
    let now: Date

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.09), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: limit.displayPercent / 100)
                    .stroke(
                        QuotaPalette.color(for: limit.level),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(QuotaCopy.percent(limit.displayPercent))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(QuotaPalette.color(for: limit.level))
            }
            .frame(width: 54, height: 54)
            Text(limit.label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .lineLimit(1)
            Text(QuotaCopy.resetCountdown(resetsAt: limit.resetsAt, now: now))
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.38))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white.opacity(0.72))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(limit.label)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let mode = limit.displayMode == .used ? "used" : "remaining"
        let reset = QuotaCopy.resetCountdown(resetsAt: limit.resetsAt, now: now)
        let state = status.text(now: now).map { ", \($0)" } ?? ""
        return "\(QuotaCopy.percent(limit.displayPercent)) \(mode), \(reset)\(state)"
    }
}
