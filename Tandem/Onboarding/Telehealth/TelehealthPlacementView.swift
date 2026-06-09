import SwiftUI

/// Telehealth electrode placement screen. Used on both ends of the call —
/// the `role` switches the image (TENS vs EMG) and the status badge to match
/// whose side this is being rendered on.
struct TelehealthPlacementView: View {
    enum Role { case patient, therapist }

    var exercise: ExerciseSelectionView.Exercise
    var role: Role
    var onContinue: () -> Void

    private var imageName: String {
        switch role {
        case .patient:   return exercise.patientElectrodeImageName
        case .therapist: return exercise.therapistElectrodeImageName
        }
    }

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
            Image(imageName)
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
            switch role {
            case .patient:   PatientUnitStatusBadge().padding(30)
            case .therapist: TherapistUnitStatusBadge().padding(30)
            }
        }
    }
}
