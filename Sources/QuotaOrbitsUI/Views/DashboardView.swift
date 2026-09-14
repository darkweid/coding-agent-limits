import QuotaOrbitsCore
import SwiftUI

@_spi(Testing)
public enum DashboardLayout {
    public static let panelWidth: CGFloat = 350
    public static let barPanelHeight: CGFloat = 406
    public static let orbitPanelHeight: CGFloat = 480
    public static let padding: CGFloat = 12
    public static let cardSpacing: CGFloat = 8
    public static let headerHeight: CGFloat = 12
    public static let barClaudeSectionHeight: CGFloat = 250
    public static let orbitClaudeSectionHeight: CGFloat = 288
    public static let nativeBarClaudeSectionHeight: CGFloat = 137
    public static let nativeOrbitClaudeSectionHeight: CGFloat = 140
    public static let baseClaudeAccountHeight: CGFloat = 105
    public static let scopedQuotaRowHeight: CGFloat = 32
    public static let orbitClaudeAccountHeight: CGFloat = 140
    public static let barCodexCardHeight: CGFloat = 104
    public static let orbitCodexCardHeight: CGFloat = 140

    public static func claudeAccountHeight(
        scopedCount: Int,
        visualStyle: QuotaVisualStyle = .bars
    ) -> CGFloat {
        switch visualStyle {
        case .bars:
            baseClaudeAccountHeight
                + CGFloat(min(max(scopedCount, 0), 1)) * scopedQuotaRowHeight
        case .orbits:
            orbitClaudeAccountHeight
        }
    }

    public static func requiredClaudeSectionHeight(
        scopedCounts: [Int],
        visualStyle: QuotaVisualStyle = .bars
    ) -> CGFloat {
        let cards = scopedCounts.map {
            claudeAccountHeight(scopedCount: $0, visualStyle: visualStyle)
        }.reduce(0, +)
        let gaps = CGFloat(max(scopedCounts.count - 1, 0)) * cardSpacing
        return cards + gaps
    }

    public static func visibleClaudeSectionHeight(
        scopedCounts: [Int],
        visualStyle: QuotaVisualStyle,
        claudeSourceMode: ClaudeSourceMode
    ) -> CGFloat {
        min(
            requiredClaudeSectionHeight(
                scopedCounts: scopedCounts,
                visualStyle: visualStyle
            ),
            claudeSectionHeight(
                for: visualStyle,
                claudeSourceMode: claudeSourceMode
            )
        )
    }

    public static func minimumCodexCardHeight(visualStyle: QuotaVisualStyle) -> CGFloat {
        switch visualStyle {
        case .bars: barCodexCardHeight
        case .orbits: orbitCodexCardHeight
        }
    }

    public static func panelHeight(
        for visualStyle: QuotaVisualStyle,
        claudeSourceMode: ClaudeSourceMode = .cswap
    ) -> CGFloat {
        if claudeSourceMode == .native {
            return totalContentHeight(
                for: visualStyle,
                claudeSourceMode: claudeSourceMode
            )
        }
        return switch visualStyle {
        case .bars: barPanelHeight
        case .orbits: orbitPanelHeight
        }
    }

    public static func claudeSectionHeight(
        for visualStyle: QuotaVisualStyle,
        claudeSourceMode: ClaudeSourceMode = .cswap
    ) -> CGFloat {
        if claudeSourceMode == .native {
            return switch visualStyle {
            case .bars: nativeBarClaudeSectionHeight
            case .orbits: nativeOrbitClaudeSectionHeight
            }
        }
        return switch visualStyle {
        case .bars: barClaudeSectionHeight
        case .orbits: orbitClaudeSectionHeight
        }
    }

    public static func totalContentHeight(
        for visualStyle: QuotaVisualStyle,
        claudeSourceMode: ClaudeSourceMode = .cswap
    ) -> CGFloat {
        padding * 2 + headerHeight
            + claudeSectionHeight(
                for: visualStyle,
                claudeSourceMode: claudeSourceMode
            )
            + minimumCodexCardHeight(visualStyle: visualStyle) + cardSpacing * 2
    }
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
    @ObservedObject private var preferences: PanelPreferences
    @ObservedObject private var actions: DashboardActions

    @MainActor
    public init(
        coordinator: QuotaRefreshCoordinator,
        preferences: PanelPreferences,
        actions: DashboardActions
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.actions = actions
    }

    public var body: some View {
        DashboardContentView(
            presentation: DashboardPresentation(
                snapshot: coordinator.snapshot,
                claudeSourceMode: preferences.claudeSourceMode
            ),
            displayMode: preferences.displayMode,
            visualStyle: preferences.visualStyle,
            claudeSourceMode: preferences.claudeSourceMode,
            actions: actions
        )
    }
}

struct DashboardContentView: View {
    let presentation: DashboardPresentation
    let displayMode: QuotaDisplayMode
    let visualStyle: QuotaVisualStyle
    let claudeSourceMode: ClaudeSourceMode
    @ObservedObject var actions: DashboardActions
    var fixedNow: Date?

    var body: some View {
        VStack(spacing: DashboardLayout.cardSpacing) {
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
                LazyVStack(spacing: DashboardLayout.cardSpacing) {
                    ForEach(presentation.accounts) { account in
                        ClaudeAccountCard(
                            account: account,
                            displayMode: displayMode,
                            visualStyle: visualStyle,
                            fixedNow: fixedNow
                        )
                        .frame(
                            minHeight: DashboardLayout.claudeAccountHeight(
                                scopedCount: account.scoped.count,
                                visualStyle: visualStyle
                            ),
                            alignment: .top
                        )
                    }
                }
            }
            .frame(
                height: DashboardLayout.visibleClaudeSectionHeight(
                    scopedCounts: presentation.accounts.map(\.scoped.count),
                    visualStyle: visualStyle,
                    claudeSourceMode: claudeSourceMode
                )
            )

            CodexQuotaCard(
                quota: presentation.codex,
                displayMode: displayMode,
                visualStyle: visualStyle,
                fixedNow: fixedNow
            )
            .frame(
                minHeight: DashboardLayout.minimumCodexCardHeight(visualStyle: visualStyle),
                maxHeight: .infinity
            )
        }
        .padding(DashboardLayout.padding)
        .frame(
            width: DashboardLayout.panelWidth,
            height: DashboardLayout.panelHeight(
                for: visualStyle,
                claudeSourceMode: claudeSourceMode
            )
        )
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
            .fixed(
                width: DashboardLayout.panelWidth,
                height: DashboardLayout.panelHeight(for: .bars)
            )
        )
    }

    @MainActor
    private static func preview(snapshot: QuotaSnapshot) -> some View {
        DashboardContentView(
            presentation: DashboardPresentation(snapshot: snapshot),
            displayMode: .used,
            visualStyle: .bars,
            claudeSourceMode: .cswap,
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
