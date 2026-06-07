import SwiftUI

/// In-clinic electrode placement screen. Therapist Mac is tiled to the left
/// half of the screen here, so this view is laid out for a narrow pane.
///
/// Layout however you like — the `onContinue` callback advances the parent's
/// flow into calibration.
struct ClinicPlacementView: View {
    var onContinue: () -> Void

    var body: some View {
        // TODO: design the in-clinic placement screen here.
        VStack(spacing: 24) {
            Spacer()
            Text("Therapist")
                .font(.custom("IBMPlexMono-Medium", size: 32))
                .multilineTextAlignment(.center)
            Text("Place the electrodes on your bicep as shown")
                .font(.custom("IBMPlexMono-Regular", size: 16))
                .foregroundStyle(.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Image("BicepEMGElectrode")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 100)
            Spacer()
            TherapistUnitStatusBadge()
                .padding(20)
            Spacer()
            Button(action: onContinue) {
                Text("Continue")
                    .font(.custom("IBMPlexMono-Medium", size: 22))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 18)
                    .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
