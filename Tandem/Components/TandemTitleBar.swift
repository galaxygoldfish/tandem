import SwiftUI

/// Custom window title content shown in the toolbar's `.principal` slot.
/// Used in place of the system-font window title so every screen displays
/// the lightning bolt icon followed by "Tandem" in Silkscreen.
struct TandemTitleBar: View {
    var body: some View {
        HStack(spacing: 4) {
            Image("LightningBolt")
                .resizable()
                .scaledToFit()
                .frame(height: 16)
            Text("Tandem")
                .font(.custom("Silkscreen-Regular", size: 15))
                .tracking(-1)
                .foregroundStyle(.black)
        }
        .padding(.leading, 7)
    }
}
