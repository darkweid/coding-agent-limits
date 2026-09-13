import SwiftUI

struct OpenAIMark: View {
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Capsule(style: .continuous)
                    .stroke(lineWidth: 1.35)
                    .frame(width: 6.5, height: 13)
                    .offset(y: -3.2)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
        .padding(1)
    }
}
