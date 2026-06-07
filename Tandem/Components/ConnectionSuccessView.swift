import SwiftUI

/// Full-screen success state shown after the telehealth link is established
/// on both sides. Animates a green circle with a checkmark and a title that
/// names who you just linked to.
struct ConnectionSuccessView: View {
    let title: String
    @State private var contentVisible = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green)
                Image(systemName: "checkmark")
                    .font(.system(size: 130, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 200, height: 200)
            .scaleEffect(contentVisible ? 1 : 0.6)
            .opacity(contentVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: contentVisible)
            Text(title)
                .font(.custom("IBMPlexMono-Medium", size: 40))
                .tracking(-1)
                .multilineTextAlignment(.center)
                .padding(.top, 50)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: contentVisible)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { contentVisible = true }
    }
}
