import SwiftUI

struct ModeSelectionView: View {
    var onLocal: () -> Void
    var onTelehealth: () -> Void
    var onBack: () -> Void

    @State private var cardsVisible = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(alignment: .center, spacing: 15) {
                Text("How are you using Tandem today?")
                    .font(.custom("IBMPlexMono-Medium", size: 40))
                    .tracking(-1)
                Text("Choose how you're connecting with your therapist today")
                    .font(.custom("IBMPlexMono-Regular", size: 16))
                    .foregroundStyle(.black.opacity(0.6))
            }
            Spacer()
            HStack(spacing: 50) {
                modeCard(
                    title: "In the clinic",
                    subtitle: "You're at an in-person physical therapy appointment with your clinician",
                    systemImage: "stethoscope",
                    action: onLocal
                )
                .scaleEffect(cardsVisible ? 1 : 0.6)
                .opacity(cardsVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: cardsVisible)
                modeCard(
                    title: "Telehealth",
                    subtitle: "You're attending your appointment virtually and you have the Patient Unit with you",
                    systemImage: "video.fill",
                    action: onTelehealth
                )
                .scaleEffect(cardsVisible ? 1 : 0.6)
                .opacity(cardsVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: cardsVisible)
            }
            Spacer()
        }
        .onAppear { cardsVisible = true }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigation) {
                TandemTitleBar()
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func modeCard(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 25) {
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 100))
                    .foregroundStyle(.primary)
                Spacer()
                Text(title)
                    .font(.custom("IBMPlexMono-Bold", size: 40))
                    .tracking(-1)
                Text(subtitle)
                    .font(.custom("IBMPlexMono-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(width: 450, height: 450)
            .padding(20)
            .contentShape(.rect(cornerRadius: 40))
            .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 40))
        }
        .buttonStyle(.plain)
    }
}
