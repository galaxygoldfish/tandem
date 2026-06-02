import SwiftUI

struct TelehealthRoleView: View {
    var onTherapist: () -> Void
    var onPatient: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("I am the...")
                .font(.title.bold())
            HStack(spacing: 20) {
                roleCard(
                    title: "Therapist",
                    subtitle: "I have the\nMuscle SpikerBox",
                    systemImage: "waveform.path.ecg",
                    action: onTherapist
                )
                roleCard(
                    title: "Patient",
                    subtitle: "I have the\nTENS unit",
                    systemImage: "bolt.heart.fill",
                    action: onPatient
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem — Telehealth")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .principal) {
                Color.clear.frame(height: 40)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func roleCard(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 220, height: 180)
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
