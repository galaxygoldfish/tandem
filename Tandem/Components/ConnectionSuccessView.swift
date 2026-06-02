import SwiftUI

/// Full-screen success state shown after the telehealth link is established
/// on both sides. Animates a green circle with a checkmark and a title that
/// names who you just linked to.
struct ConnectionSuccessView: View {
    let title: String
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green)
                Image(systemName: "checkmark")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 140, height: 140)
            .scaleEffect(didAppear ? 1.0 : 0.3)
            .opacity(didAppear ? 1.0 : 0)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .opacity(didAppear ? 1.0 : 0)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                didAppear = true
            }
        }
    }
}
