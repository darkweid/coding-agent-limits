import Combine
import Foundation

public enum ClaudeSourceMode: String, CaseIterable, Identifiable, Sendable {
    case cswap
    case nativeClaudeCode

    public var id: Self { self }
}

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

@MainActor
public final class AppPreferences: ObservableObject {
    public static let defaultCswapPath = ExecutablePathResolver.defaultCswapPath(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
    )
    public static let defaultClaudePath = ExecutablePathResolver.defaultClaudePath(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: FileManager.default.isExecutableFile(atPath:)
    )
    public static let defaultCodexPath = ExecutablePathResolver.defaultCodexPath(
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
        cswapPath = defaults.string(forKey: Keys.cswapPath) ?? Self.defaultCswapPath
        claudePath = defaults.string(forKey: Keys.claudePath) ?? Self.defaultClaudePath
        codexPath = defaults.string(forKey: Keys.codexPath) ?? Self.defaultCodexPath
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
        isPinned =
            defaults.object(forKey: Keys.isPinned) == nil
            ? true : defaults.bool(forKey: Keys.isPinned)
    }

    private static func normalizedRefreshInterval(_ value: Int) -> Int {
        let clamped = min(max(value, 30), 600)
        return Int((Double(clamped) / 30).rounded()) * 30
    }
}
