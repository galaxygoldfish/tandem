import SwiftUI

/// Telehealth electrode placement screen. Therapist Mac fills the whole
/// screen here (no patient pane beside it), so this view has more room.
///
/// Layout however you like — the `onContinue` callback advances the parent's
/// flow into calibration.
struct TelehealthPlacementView: View {
    var exercise: ExerciseSelectionView.Exercise
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Place your electrodes")
                .font(.custom("IBMPlexMono-Medium", size: 40))
                .tracking(-1)
                .multilineTextAlignment(.center)
            Text("Place the electrodes on your \(exercise.bodyPart) as shown, then press continue")
                .font(.custom("IBMPlexMono-Regular", size: 18))
                .foregroundStyle(.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Image(exercise.electrodeImageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 580, maxHeight: 460)
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
        .overlay(alignment: .bottomLeading) {
            TherapistUnitStatusBadge()
                .padding(30)
        }
    }
}
