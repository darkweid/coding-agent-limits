import Combine
import Foundation

public enum QuotaDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case used
    case remaining

    public var id: Self { self }
}

public enum QuotaVisualStyle: String, CaseIterable, Identifiable, Sendable {
    case bars
    case orbits

    public var id: Self { self }
}

public enum ClaudeSourceMode: String, CaseIterable, Identifiable, Sendable {
    case cswap
    case native

    public var id: Self { self }
}

@MainActor
public final class PanelPreferences: ObservableObject {
    public static let defaultCswapPath = ExecutablePathResolver.defaultCswapPath(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
    )
    public static let defaultCodexPath = ExecutablePathResolver.defaultCodexPath(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: FileManager.default.isExecutableFile(atPath:)
    )
    public static let defaultClaudePath = ExecutablePathResolver.defaultClaudePath(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: FileManager.default.isExecutableFile(atPath:)
    )

    @Published public var claudeSourceMode: ClaudeSourceMode {
        didSet { defaults.set(claudeSourceMode.rawValue, forKey: Keys.claudeSourceMode) }
    }

    @Published public var cswapPath: String {
        didSet { defaults.set(cswapPath, forKey: Keys.cswapPath) }
    }

    @Published public var claudePath: String {
        didSet { defaults.set(claudePath, forKey: Keys.claudePath) }
    }

    @Published public var codexPath: String {
        didSet { defaults.set(codexPath, forKey: Keys.codexPath) }
    }

    @Published public var refreshIntervalSeconds: Int {
        didSet {
            let normalized = Self.normalizedRefreshInterval(refreshIntervalSeconds)
            if normalized != refreshIntervalSeconds {
                refreshIntervalSeconds = normalized
                return
            }
            defaults.set(normalized, forKey: Keys.refreshIntervalSeconds)
        }
    }

    @Published public var displayMode: QuotaDisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    @Published public var visualStyle: QuotaVisualStyle {
        didSet { defaults.set(visualStyle.rawValue, forKey: Keys.visualStyle) }
    }

    @Published public var panelOrigin: CGPoint? {
        didSet {
            guard let panelOrigin else {
                defaults.removeObject(forKey: Keys.panelOriginX)
                defaults.removeObject(forKey: Keys.panelOriginY)
                return
            }
            defaults.set(Double(panelOrigin.x), forKey: Keys.panelOriginX)
            defaults.set(Double(panelOrigin.y), forKey: Keys.panelOriginY)
        }
    }

    @Published public var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: Keys.isPinned) }
    }

    private enum Keys {
        static let claudeSourceMode = "quotaOrbits.claudeSourceMode"
        static let cswapPath = "quotaOrbits.cswapPath"
        static let claudePath = "quotaOrbits.claudePath"
        static let codexPath = "quotaOrbits.codexPath"
        static let refreshIntervalSeconds = "quotaOrbits.refreshIntervalSeconds"
        static let displayMode = "quotaOrbits.displayMode"
        static let visualStyle = "quotaOrbits.visualStyle"
        static let panelOriginX = "quotaOrbits.panelOrigin.x"
        static let panelOriginY = "quotaOrbits.panelOrigin.y"
        static let isPinned = "quotaOrbits.isPinned"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        claudeSourceMode =
            defaults.string(forKey: Keys.claudeSourceMode)
            .flatMap(ClaudeSourceMode.init(rawValue:)) ?? .cswap
        cswapPath =
            defaults.string(forKey: Keys.cswapPath)
            ?? Self.defaultCswapPath
        claudePath =
            defaults.string(forKey: Keys.claudePath)
            ?? Self.defaultClaudePath
        codexPath =
            defaults.string(forKey: Keys.codexPath)
            ?? Self.defaultCodexPath
        let storedInterval =
            defaults.object(forKey: Keys.refreshIntervalSeconds) == nil
            ? 60 : defaults.integer(forKey: Keys.refreshIntervalSeconds)
        refreshIntervalSeconds = Self.normalizedRefreshInterval(storedInterval)
        displayMode =
            defaults.string(forKey: Keys.displayMode)
            .flatMap(QuotaDisplayMode.init(rawValue:)) ?? .used
        visualStyle =
            defaults.string(forKey: Keys.visualStyle)
            .flatMap(QuotaVisualStyle.init(rawValue:)) ?? .bars

        if defaults.object(forKey: Keys.panelOriginX) != nil,
            defaults.object(forKey: Keys.panelOriginY) != nil
        {
            panelOrigin = CGPoint(
                x: defaults.double(forKey: Keys.panelOriginX),
                y: defaults.double(forKey: Keys.panelOriginY)
            )
        } else {
            panelOrigin = nil
        }

        if defaults.object(forKey: Keys.isPinned) == nil {
            isPinned = true
        } else {
            isPinned = defaults.bool(forKey: Keys.isPinned)
        }
    }

    private static func normalizedRefreshInterval(_ value: Int) -> Int {
        let clamped = min(max(value, 30), 600)
        return Int((Double(clamped) / 30).rounded()) * 30
    }
}

@_spi(Testing)
public enum PanelPlacement {
    public static func targetScreenFrame(
        for windowFrame: CGRect,
        screenFrames: [CGRect]
    ) -> CGRect? {
        screenFrames
            .filter { $0.width > 0 && $0.height > 0 && !$0.isNull && !$0.isInfinite }
            .max {
                suitability(of: $0, for: windowFrame)
                    < suitability(of: $1, for: windowFrame)
            }
    }

    public static func clampedOrigin(
        _ origin: CGPoint,
        panelSize: CGSize,
        screenFrames: [CGRect]
    ) -> CGPoint {
        let screens = screenFrames.filter {
            $0.width > 0 && $0.height > 0 && !$0.isNull && !$0.isInfinite
        }
        guard !screens.isEmpty else { return origin }

        let proposed = CGRect(origin: origin, size: panelSize)
        let target = targetScreenFrame(for: proposed, screenFrames: screens) ?? screens[0]

        let maximumX = max(target.minX, target.maxX - panelSize.width)
        let maximumY = max(target.minY, target.maxY - panelSize.height)
        return CGPoint(
            x: min(max(origin.x, target.minX), maximumX),
            y: min(max(origin.y, target.minY), maximumY)
        )
    }

    private static func suitability(
        of screen: CGRect,
        for panel: CGRect
    ) -> Double {
        let intersection = screen.intersection(panel)
        if !intersection.isNull, !intersection.isEmpty {
            return 1_000_000_000 + Double(intersection.width * intersection.height)
        }

        let deltaX: Double
        if panel.maxX < screen.minX {
            deltaX = screen.minX - panel.maxX
        } else if panel.minX > screen.maxX {
            deltaX = panel.minX - screen.maxX
        } else {
            deltaX = 0
        }

        let deltaY: Double
        if panel.maxY < screen.minY {
            deltaY = screen.minY - panel.maxY
        } else if panel.minY > screen.maxY {
            deltaY = panel.minY - screen.maxY
        } else {
            deltaY = 0
        }
        return -(deltaX * deltaX + deltaY * deltaY)
    }
}
