import QuotaOrbitsCore
import SwiftUI

struct CodexQuotaCard: View {
    let quota: CodexCardPresentation
    let displayMode: QuotaDisplayMode
    let visualStyle: QuotaVisualStyle
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
                OpenAIMark()
                    .frame(
                        width: ProviderMarkMetrics.canvasSize,
                        height: ProviderMarkMetrics.canvasSize
                    )
                    .foregroundStyle(Color.white.opacity(0.72))
                    .accessibilityLabel(ProviderHeaderCopy.openAIAccessibilityLabel)

                Text(ProviderHeaderCopy.codexTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))

                if let balance = quota.creditsBalance {
                    Text("credits \(QuotaCopy.credits(balance))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .accessibilityLabel("Credits \(QuotaCopy.credits(balance))")
                }
                ProviderActiveIndicator(provider: .codex, isActive: quota.isActive)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                ProviderHeaderCopy.codexAccessibilityLabel(isActive: quota.isActive)
            )

            Group {
                if visualStyle == .orbits {
                    HStack(spacing: 6) {
                        quotaGauge(window: "5 hours", quotaWindow: quota.fiveHour, now: now)
                        quotaGauge(window: "7 days", quotaWindow: quota.weekly, now: now)
                    }
                } else {
                    quotaGauge(window: "5 hours", quotaWindow: quota.fiveHour, now: now)
                    quotaGauge(window: "7 days", quotaWindow: quota.weekly, now: now)
                }
            }

            statusLine(now: now)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
    }

    private func quotaGauge(
        window: String,
        quotaWindow: QuotaWindow?,
        now: Date
    ) -> some View {
        QuotaGaugeView(
            window: window,
            countdown: quota.status.resetCountdown(window: quotaWindow, now: now),
            usedPercent: quotaWindow?.usedPercent,
            dataState: quota.status.barDataState,
            displayMode: displayMode,
            visualStyle: visualStyle
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
