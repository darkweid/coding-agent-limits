import QuotaOrbitsCore
import SwiftUI

@_spi(Testing)
public enum DashboardLayout {
    public static let panelWidth: CGFloat = 350
    public static let panelHeight: CGFloat = 406
    public static let padding: CGFloat = 12
    public static let sectionSpacing: CGFloat = 8
    public static let headerHeight: CGFloat = 12
    public static let claudeSectionHeight: CGFloat = 250
    public static let claudeAccountSpacing: CGFloat = 8
    public static let baseClaudeAccountHeight: CGFloat = 105
    public static let scopedQuotaRowHeight: CGFloat = 32
    public static let codexCardHeight: CGFloat = 104

    public static func claudeAccountHeight(scopedCount: Int) -> CGFloat {
        baseClaudeAccountHeight + CGFloat(min(max(scopedCount, 0), 1)) * scopedQuotaRowHeight
    }

    public static func requiredClaudeSectionHeight(scopedCounts: [Int]) -> CGFloat {
        let cards = scopedCounts.map(claudeAccountHeight(scopedCount:)).reduce(0, +)
        let gaps = CGFloat(max(scopedCounts.count - 1, 0)) * claudeAccountSpacing
        return cards + gaps
    }

    public static let totalContentHeight =
        padding * 2 + headerHeight + claudeSectionHeight + codexCardHeight + sectionSpacing * 2
}

@MainActor
public final class DashboardActions: ObservableObject {
    @Published public var isPinned: Bool
    public let refreshNow: () -> Void
    public let togglePinned: () -> Void
    public let openSettings: () -> Void
    public let quit: () -> Void

    public init(
        isPinned: Bool,
        refreshNow: @escaping () -> Void,
        togglePinned: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.isPinned = isPinned
        self.refreshNow = refreshNow
        self.togglePinned = togglePinned
        self.openSettings = openSettings
        self.quit = quit
    }
}

public struct DashboardView: View {
    @ObservedObject private var coordinator: QuotaRefreshCoordinator
    @ObservedObject private var actions: DashboardActions

    @MainActor
    public init(
        coordinator: QuotaRefreshCoordinator,
        actions: DashboardActions
    ) {
        self.coordinator = coordinator
        self.actions = actions
    }

    public var body: some View {
        DashboardContentView(
            presentation: DashboardPresentation(snapshot: coordinator.snapshot),
            actions: actions
        )
    }
}

struct DashboardContentView: View {
    let presentation: DashboardPresentation
    @ObservedObject var actions: DashboardActions
    var fixedNow: Date?

    var body: some View {
        VStack(spacing: DashboardLayout.sectionSpacing) {
            HStack {
                Spacer()
                if let date = presentation.lastSuccessfulRefreshAt {
                    Text(QuotaCopy.lastRefresh(date))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
            }
            .frame(height: DashboardLayout.headerHeight)

            ScrollView(.vertical) {
                LazyVStack(spacing: DashboardLayout.claudeAccountSpacing) {
                    ForEach(presentation.accounts) { account in
                        ClaudeAccountCard(account: account, fixedNow: fixedNow)
                            .frame(
                                height: DashboardLayout.claudeAccountHeight(
                                    scopedCount: account.scoped.count
                                )
                            )
                    }
                }
            }
            .frame(height: DashboardLayout.claudeSectionHeight)

            CodexQuotaCard(quota: presentation.codex, fixedNow: fixedNow)
                .frame(height: DashboardLayout.codexCardHeight)
        }
        .padding(DashboardLayout.padding)
        .frame(width: DashboardLayout.panelWidth, height: DashboardLayout.panelHeight)
        .background(panelBackground)
        .contextMenu {
            let labels = DashboardCopy.contextActions(isPinned: actions.isPinned)
            Button(labels[0], action: actions.refreshNow)
            Button(labels[1], action: actions.togglePinned)
            Divider()
            Button(labels[2], action: actions.openSettings)
            Button(labels[3], action: actions.quit)
        }
        .preferredColorScheme(.dark)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.055, green: 0.057, blue: 0.062).opacity(0.90))
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
        }
    }
}

private enum DashboardPreviewFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func window(remaining: Double, hours: Double) -> QuotaWindow {
        QuotaWindow(
            usedPercent: 100 - remaining,
            resetsAt: now.addingTimeInterval(hours * 3_600)
        )
    }

    static func account(
        id: String,
        alias: String,
        active: Bool,
        fiveHour: Double,
        weekly: Double
    ) -> ClaudeAccountQuota {
        ClaudeAccountQuota(
            id: id,
            alias: alias,
            isActive: active,
            fiveHour: window(remaining: fiveHour, hours: 3.5),
            weekly: window(remaining: weekly, hours: 61)
        )
    }

    static let accounts = [
        account(id: "one", alias: "max", active: false, fiveHour: 100, weekly: 81),
        account(id: "two", alias: "pro", active: true, fiveHour: 28, weekly: 93),
    ]

    static let quota = CodexQuota(
        fiveHour: window(remaining: 75, hours: 2.5),
        weekly: window(remaining: 50, hours: 72),
        creditsBalance: Decimal(string: "411.51")
    )

    static let available = QuotaSnapshot(
        claude: .available(accounts, updatedAt: now),
        codex: .available(quota, updatedAt: now),
        lastCycleStartedAt: now
    )

    static let stale = QuotaSnapshot(
        claude: .stale(
            accounts, lastSuccessAt: now.addingTimeInterval(-480), message: "unavailable"),
        codex: .stale(quota, lastSuccessAt: now.addingTimeInterval(-180), message: "unavailable"),
        lastCycleStartedAt: now
    )

    static let unavailable = QuotaSnapshot(
        claude: .unavailable(message: "unavailable"),
        codex: .unavailable(message: "unavailable"),
        lastCycleStartedAt: now
    )

    static let loading = QuotaSnapshot.initial

    static let thresholdEdges = QuotaSnapshot(
        claude: .available(
            [
                account(id: "one", alias: "19", active: true, fiveHour: 19, weekly: 0),
                account(id: "two", alias: "20", active: false, fiveHour: 51, weekly: 20),
            ],
            updatedAt: now
        ),
        codex: .available(
            CodexQuota(
                fiveHour: window(remaining: 72, hours: 2.5),
                weekly: window(remaining: 19, hours: 72),
                creditsBalance: nil
            ),
            updatedAt: now
        ),
        lastCycleStartedAt: now
    )

    static let aliasFallback = QuotaSnapshot(
        claude: .available(
            [
                account(id: "one", alias: "", active: true, fiveHour: 100, weekly: 81),
                account(id: "two", alias: "   ", active: false, fiveHour: 28, weekly: 93),
            ],
            updatedAt: now
        ),
        codex: .available(quota, updatedAt: now),
        lastCycleStartedAt: now
    )

    static let longAlias = QuotaSnapshot(
        claude: .available(
            [
                account(
                    id: "one", alias: "unusually-long-neutral-name", active: true, fiveHour: 100,
                    weekly: 81),
                account(id: "two", alias: "02", active: false, fiveHour: 28, weekly: 93),
            ],
            updatedAt: now
        ),
        codex: .available(quota, updatedAt: now),
        lastCycleStartedAt: now
    )
}

struct DashboardView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            preview(snapshot: DashboardPreviewFixtures.available)
                .previewDisplayName("Available")
            preview(snapshot: DashboardPreviewFixtures.available)
                .environment(\.colorScheme, .light)
                .previewDisplayName("Light System")
            preview(snapshot: DashboardPreviewFixtures.loading)
                .previewDisplayName("Loading")
            preview(snapshot: DashboardPreviewFixtures.stale)
                .previewDisplayName("Stale")
            preview(snapshot: DashboardPreviewFixtures.unavailable)
                .previewDisplayName("Unavailable")
            preview(snapshot: DashboardPreviewFixtures.thresholdEdges)
                .previewDisplayName("Thresholds 19 and 0")
            preview(snapshot: DashboardPreviewFixtures.aliasFallback)
                .previewDisplayName("Fallback Aliases")
            preview(snapshot: DashboardPreviewFixtures.longAlias)
                .previewDisplayName("Long Alias")
        }
        .previewLayout(
            .fixed(width: DashboardLayout.panelWidth, height: DashboardLayout.panelHeight)
        )
    }

    @MainActor
    private static func preview(snapshot: QuotaSnapshot) -> some View {
        DashboardContentView(
            presentation: DashboardPresentation(snapshot: snapshot),
            actions: DashboardActions(
                isPinned: true,
                refreshNow: {},
                togglePinned: {},
                openSettings: {},
                quit: {}
            ),
            fixedNow: DashboardPreviewFixtures.now
        )
    }
}
