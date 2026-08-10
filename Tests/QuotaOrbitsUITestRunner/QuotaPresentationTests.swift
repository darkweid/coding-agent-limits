import Foundation
import QuotaOrbitsCore
@_spi(Testing) import QuotaOrbitsUI

enum QuotaPresentationTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    static let cases: [TestCase] = [
        TestCase(name: "QuotaFeedPresentationTests.testProjectsUnlimitedAccountsAndScopedLimits") {
            let snapshot = QuotaFeedSnapshot(entries: [
                .init(
                    sourceID: .cswap,
                    snapshot: .available(
                        ProviderQuota(
                            providerID: .claude,
                            accounts: [
                                neutralAccount(index: 1),
                                neutralAccount(index: 2),
                                neutralAccount(index: 3),
                            ]
                        ),
                        updatedAt: now
                    )
                )
            ])

            let presentation = QuotaFeedPresentation(snapshot: snapshot, displayMode: .used)

            try TestSupport.assertEqual(presentation.cards.count, 3)
            try TestSupport.assertEqual(presentation.cards.map(\.alias), ["safe", "02", "03"])
            try TestSupport.assertEqual(
                presentation.cards[2].limits.map(\.label), ["Weekly", "Fable"]
            )
        },
        TestCase(name: "QuotaFeedPresentationTests.testRemainingChangesValueButNotSeverity") {
            let limit = QuotaLimit(
                id: "weekly",
                label: "Weekly",
                usedPercent: 90,
                resetsAt: now.addingTimeInterval(3_600)
            )
            let snapshot = QuotaFeedSnapshot(entries: [
                .init(
                    sourceID: .codexAppServer,
                    snapshot: .available(
                        ProviderQuota(
                            providerID: .codex,
                            accounts: [
                                QuotaAccount(
                                    id: "private",
                                    alias: "Codex account",
                                    isActive: true,
                                    state: .fresh,
                                    limits: [limit]
                                )
                            ]
                        ),
                        updatedAt: now
                    )
                )
            ])

            let presentation = QuotaFeedPresentation(
                snapshot: snapshot,
                displayMode: .remaining
            )
            let projected = presentation.cards[0].limits[0]

            try TestSupport.assertEqual(projected.displayPercent, 10)
            try TestSupport.assertEqual(projected.displayMode, .remaining)
            try TestSupport.assertEqual(projected.level, .critical)
            try TestSupport.assertEqual(presentation.cards[0].alias, "01")
            try TestSupport.assertEqual(presentation.cards[0].symbol, .codex)
        },
        TestCase(name: "QuotaFeedPresentationTests.testKeepsSourceOrderAndSanitizesFailures") {
            let snapshot = QuotaFeedSnapshot(entries: [
                .init(
                    sourceID: .claudeCode,
                    snapshot: .stale(
                        ProviderQuota(
                            providerID: .claude,
                            accounts: [neutralAccount(index: 1, alias: "user@example.com")]
                        ),
                        lastSuccessAt: now.addingTimeInterval(-120),
                        message: "private provider output"
                    )
                ),
                .init(
                    sourceID: .codexAppServer,
                    snapshot: .unavailable(message: "private transport output")
                ),
            ])

            let presentation = QuotaFeedPresentation(snapshot: snapshot, displayMode: .used)

            try TestSupport.assertEqual(presentation.cards.map(\.alias), ["01", "02"])
            try TestSupport.assertEqual(presentation.cards.map(\.symbol), [.claude, .codex])
            try TestSupport.assertEqual(
                presentation.cards[0].status.text(now: now), "updated 2 min ago"
            )
            try TestSupport.assertEqual(presentation.cards[1].status.text(now: now), "no data")
        },
        TestCase(name: "QuotaFeedPresentationTests.testLoadingUsesNeutralPlaceholders") {
            let presentation = QuotaFeedPresentation(
                snapshot: QuotaFeedSnapshot(entries: [
                    .init(sourceID: .cswap, snapshot: .loading),
                    .init(sourceID: .codexAppServer, snapshot: .loading),
                ]),
                displayMode: .used
            )

            try TestSupport.assertEqual(presentation.cards.map(\.alias), ["01", "02"])
            try TestSupport.assertEqual(presentation.cards.map(\.limits), [[], []])
            try TestSupport.assertEqual(
                presentation.cards.map { $0.status.text(now: now) }, [nil, nil]
            )
            try TestSupport.assertEqual(presentation.lastSuccessfulRefreshAt, nil)
        },
        TestCase(name: "QuotaPresentationTests.testQuotaCopyFormatsValuesForDisplay") {
            guard let credits = Decimal(string: "411.5127706250") else {
                throw AssertionFailure(message: "Could not create the credits fixture")
            }
            try TestSupport.assertEqual(QuotaCopy.percent(28.4), "28%")
            try TestSupport.assertEqual(QuotaCopy.percent(nil), "—")
            try TestSupport.assertEqual(
                QuotaCopy.resetCountdown(
                    resetsAt: now.addingTimeInterval(205 * 60),
                    now: now
                ),
                "resets in 3h 25m"
            )
            try TestSupport.assertEqual(
                QuotaCopy.resetCountdown(resetsAt: nil, now: now), "no data")
            try TestSupport.assertEqual(
                QuotaCopy.stale(lastSuccessAt: now.addingTimeInterval(-125), now: now),
                "updated 2 min ago"
            )
            try TestSupport.assertEqual(QuotaCopy.credits(credits), "411.51")
        },
        TestCase(name: "QuotaPresentationTests.testContextActionsUseNeutralApprovedCopy") {
            try TestSupport.assertEqual(
                DashboardCopy.contextActions(isPinned: true),
                ["Refresh Now", "Move", "Settings…", "Quit"]
            )
            try TestSupport.assertEqual(
                DashboardCopy.contextActions(isPinned: false),
                ["Refresh Now", "Pin", "Settings…", "Quit"]
            )
        },
        TestCase(name: "QuotaLimitBarTests.testFillNormalizationStaysInsideTrack") {
            try TestSupport.assertEqual(QuotaLimitBarMetrics.normalized(-5), 0)
            try TestSupport.assertEqual(QuotaLimitBarMetrics.normalized(43), 43)
            try TestSupport.assertEqual(QuotaLimitBarMetrics.normalized(105), 100)
        },
        TestCase(name: "SettingsViewTests.testLaunchAtLoginNoticeUsesNeutralCopy") {
            try TestSupport.assertEqual(LaunchAtLoginNotice.updated.text, "Setting saved")
            try TestSupport.assertFalse(LaunchAtLoginNotice.updated.isFailure)
            try TestSupport.assertEqual(
                LaunchAtLoginNotice.updateFailed.text, "Could not change setting"
            )
            try TestSupport.assertTrue(LaunchAtLoginNotice.updateFailed.isFailure)
        },
        TestCase(name: "SettingsViewTests.testSourceVisibilityAndRefreshLabels") {
            try TestSupport.assertEqual(SettingsPresentation.pathKind(for: .cswap), .cswap)
            try TestSupport.assertEqual(
                SettingsPresentation.pathKind(for: .nativeClaudeCode), .claudeCode
            )
            try TestSupport.assertEqual(SettingsPresentation.refreshLabel(seconds: 30), "30 sec")
            try TestSupport.assertEqual(SettingsPresentation.refreshLabel(seconds: 600), "10 min")
        },
    ]

    private static func neutralAccount(index: Int, alias: String? = nil) -> QuotaAccount {
        QuotaAccount(
            id: "private-\(index)",
            alias: alias ?? (index == 1 ? "safe" : ""),
            isActive: index == 2,
            state: .fresh,
            limits: [
                QuotaLimit(
                    id: "weekly",
                    label: "Weekly",
                    usedPercent: Double(index * 10),
                    resetsAt: now.addingTimeInterval(3_600)
                ),
                QuotaLimit(
                    id: "fable",
                    label: "Fable",
                    usedPercent: Double(index * 20),
                    resetsAt: now.addingTimeInterval(7_200)
                ),
            ]
        )
    }
}
