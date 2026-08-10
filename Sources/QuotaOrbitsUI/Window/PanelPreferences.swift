import Combine
import Foundation

@MainActor
public final class PanelPreferences: ObservableObject {
    public static let defaultCswapPath = ExecutablePathResolver.defaultCswapPath(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
    )
    public static let defaultCodexPath = ExecutablePathResolver.defaultCodexPath(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: FileManager.default.isExecutableFile(atPath:)
    )

    @Published public var cswapPath: String {
        didSet { defaults.set(cswapPath, forKey: Keys.cswapPath) }
    }

    @Published public var codexPath: String {
        didSet { defaults.set(codexPath, forKey: Keys.codexPath) }
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
        static let cswapPath = "quotaOrbits.cswapPath"
        static let codexPath = "quotaOrbits.codexPath"
        static let panelOriginX = "quotaOrbits.panelOrigin.x"
        static let panelOriginY = "quotaOrbits.panelOrigin.y"
        static let isPinned = "quotaOrbits.isPinned"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cswapPath = defaults.string(forKey: Keys.cswapPath)
            ?? Self.defaultCswapPath
        codexPath = defaults.string(forKey: Keys.codexPath)
            ?? Self.defaultCodexPath

        if defaults.object(forKey: Keys.panelOriginX) != nil,
           defaults.object(forKey: Keys.panelOriginY) != nil {
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
}

@_spi(Testing)
public enum PanelPlacement {
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
        let target = screens.max { lhs, rhs in
            suitability(of: lhs, for: proposed)
                < suitability(of: rhs, for: proposed)
        } ?? screens[0]

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
            return 1_000_000_000 + intersection.width * intersection.height
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
