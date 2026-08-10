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
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Text(quota.symbol)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))

                if let balance = quota.creditsBalance {
                    Text("credits \(QuotaCopy.credits(balance))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .accessibilityLabel("Credits \(QuotaCopy.credits(balance))")
                }
                Spacer()
            }

            QuotaBarView(
                window: "7 days",
                countdown: quota.status.resetCountdown(
                    window: quota.weekly,
                    now: now
                ),
                usedPercent: quota.weekly?.usedPercent,
                dataState: quota.status.barDataState
            )

            statusLine(now: now)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
    }

    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        if let text = quota.status.text(now: now) {
            HStack(spacing: 4) {
                if quota.status.isStale {
                    Circle()
                        .fill(QuotaPalette.color(for: .warning))
                        .frame(width: 5, height: 5)
                }
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.46))
        } else {
            Color.clear.frame(height: 10)
        }
    }
}
