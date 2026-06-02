import SwiftUI

struct ModeSelectionView: View {
    var onLocal: () -> Void
    var onTelehealth: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("How will you use Tandem?")
                .font(.title.bold())
            Text("Choose how the therapist and patient are connected")
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                modeCard(
                    title: "Local",
                    subtitle: "Both devices connected\nto this Mac",
                    systemImage: "cable.connector",
                    action: onLocal
                )
                modeCard(
                    title: "Telehealth",
                    subtitle: "Therapist and patient\non separate Macs",
                    systemImage: "wifi",
                    action: onTelehealth
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

    private func modeCard(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
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
