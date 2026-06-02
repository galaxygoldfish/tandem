import SwiftUI

struct TelehealthRoleView: View {
    var onTherapist: () -> Void
    var onPatient: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("I'm the...")
                .font(.title.bold())
            Spacer()
            HStack(spacing: 20) {
                roleCard(
                    title: "Therapist",
                    subtitle: "",
                    systemImage: "waveform.path.ecg",
                    color: .blue.opacity(0.5),
                    action: onTherapist
                )
                roleCard(
                    title: "Patient",
                    subtitle: "",
                    systemImage: "bolt.fill",
                    color: .purple.opacity(0.5),
                    action: onPatient
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem")
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

    private func roleCard(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 80))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.title)
            }
            .frame(width: 220, height: 180)
            .padding(20)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
