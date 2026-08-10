import Foundation

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
        let target =
            screens.max { lhs, rhs in
                suitability(of: lhs, for: proposed) < suitability(of: rhs, for: proposed)
            } ?? screens[0]
        let maximumX = max(target.minX, target.maxX - panelSize.width)
        let maximumY = max(target.minY, target.maxY - panelSize.height)
        return CGPoint(
            x: min(max(origin.x, target.minX), maximumX),
            y: min(max(origin.y, target.minY), maximumY)
        )
    }

    private static func suitability(of screen: CGRect, for panel: CGRect) -> Double {
        let intersection = screen.intersection(panel)
        if !intersection.isNull, !intersection.isEmpty {
            return 1_000_000_000 + Double(intersection.width * intersection.height)
        }
        let deltaX =
            panel.maxX < screen.minX
            ? screen.minX - panel.maxX
            : (panel.minX > screen.maxX ? panel.minX - screen.maxX : 0)
        let deltaY =
            panel.maxY < screen.minY
            ? screen.minY - panel.maxY
            : (panel.minY > screen.maxY ? panel.minY - screen.maxY : 0)
        return -(deltaX * deltaX + deltaY * deltaY)
    }
}
