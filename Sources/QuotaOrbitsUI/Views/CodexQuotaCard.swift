import SwiftUI

struct CodexQuotaCard: View {
    let quota: CodexCardPresentation
    var fixedNow: Date?

    var body: some View {
        Group {
            if let fixedNow {
                content(now: fixedNow)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    content(now: context.date)
                }
            }
        }
    }

    private func content(now: Date) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(quota.symbol)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))

                if let balance = quota.creditsBalance {
                    Text(QuotaCopy.credits(balance))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .accessibilityLabel("Баланс \(QuotaCopy.credits(balance))")
                }
            }
            .frame(width: 62, alignment: .leading)

            OrbitGaugeView(
                weeklyRemainingPercent: quota.weekly?.remainingPercent
            )
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 8) {
                Text(QuotaCopy.reset(prefix: "7д", window: quota.weekly, now: now))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                statusLine(now: now)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
    }

    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        if let text = quota.status.text(now: now) {
            HStack(spacing: 4) {
                if quota.status.isStale {
                    Circle()
                        .fill(QuotaPalette.color(for: .low))
                        .frame(width: 5, height: 5)
                }
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.46))
        } else {
            Color.clear.frame(height: 11)
        }
    }
}
