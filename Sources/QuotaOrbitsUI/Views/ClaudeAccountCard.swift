import SwiftUI

struct ClaudeAccountCard: View {
    let account: AccountCardPresentation
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
            HStack(spacing: 6) {
                Text(ProviderHeaderCopy.claudeMark)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.85, green: 0.43, blue: 0.29))
                    .accessibilityHidden(true)
                Text(account.alias)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
                if account.isActive {
                    Circle()
                        .fill(QuotaPalette.color(for: .healthy))
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Active account")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                ProviderHeaderCopy.claudeAccessibilityLabel(
                    alias: account.alias,
                    isActive: account.isActive
                )
            )

            QuotaBarView(
                window: "5 hours",
                countdown: account.status.resetCountdown(
                    window: account.fiveHour,
                    now: now
                ),
                usedPercent: account.fiveHour?.usedPercent,
                dataState: account.status.barDataState
            )

            QuotaBarView(
                window: "7 days",
                countdown: account.status.resetCountdown(
                    window: account.weekly,
                    now: now
                ),
                usedPercent: account.weekly?.usedPercent,
                dataState: account.status.barDataState
            )

            ForEach(Array(account.scoped.enumerated()), id: \.offset) { _, scoped in
                QuotaBarView(
                    window: scoped.label,
                    countdown: account.status.resetCountdown(
                        window: scoped.window,
                        now: now
                    ),
                    usedPercent: scoped.window.usedPercent,
                    dataState: account.status.barDataState
                )
            }

            statusLine(now: now)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
    }

    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        if let text = account.status.text(now: now) {
            HStack(spacing: 4) {
                if account.status.isStale {
                    Circle()
                        .fill(QuotaPalette.color(for: .warning))
                        .frame(width: 5, height: 5)
                }
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.46))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(height: 10)
        }
    }
}
