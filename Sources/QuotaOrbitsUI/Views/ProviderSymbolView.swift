import AppKit
import SwiftUI

struct ProviderSymbolView: View {
    let symbol: ProviderSymbol

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "circle.hexagongrid.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: 16, height: 16)
        .foregroundStyle(Color.white.opacity(0.72))
        .accessibilityLabel(symbol.accessibilityLabel)
    }

    private var image: NSImage? {
        let name = symbol == .claude ? "ClaudeSymbol" : "OpenAIBlossom"
        let resourceBundle: Bundle
        if let bundleURL = Bundle.main.url(
            forResource: "QuotaOrbits_QuotaOrbitsUI",
            withExtension: "bundle"
        ), let bundledResources = Bundle(url: bundleURL) {
            resourceBundle = bundledResources
        } else {
            resourceBundle = .module
        }
        guard let url = resourceBundle.url(forResource: name, withExtension: "svg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
