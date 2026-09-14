import SwiftUI

@_spi(Testing)
public enum ProviderMarkMetrics {
    public static let canvasSize: CGFloat = 16
    public static let claudeVisibleDiameter: CGFloat = 15
    public static let openAIVisibleDiameter: CGFloat = 15
    public static let openAILobeHeight = openAIVisibleDiameter * 2 / 3
    public static let openAILobeOffset = openAIVisibleDiameter / 6
    public static let openAIOuterRadius = openAILobeHeight / 2 + openAILobeOffset
}

struct ClaudeMark: View {
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule(style: .continuous)
                    .frame(width: 2, height: ProviderMarkMetrics.claudeVisibleDiameter / 2)
                    .offset(y: -ProviderMarkMetrics.claudeVisibleDiameter / 4)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
        }
    }
}

struct OpenAIMark: View {
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Capsule(style: .continuous)
                    .strokeBorder(lineWidth: 1.35)
                    .frame(
                        width: ProviderMarkMetrics.openAIVisibleDiameter * 0.347,
                        height: ProviderMarkMetrics.openAILobeHeight
                    )
                    .offset(y: -ProviderMarkMetrics.openAILobeOffset)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
    }
}
