import SwiftUI
import ORSSerial

/// Therapist onboarding flow: electrode placement → baseline capture → MVC
/// capture → `TherapistSessionView`. Also opens (and tiles) the patient
/// window, and broadcasts calibration completion to it via `SerialManager`.
struct TherapistView: View {
    @EnvironmentObject var serialManager: SerialManager
    @EnvironmentObject private var networkManager: NetworkManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step: Step = .placement
    /// The therapist's own NSWindow, captured via `WindowAccessor` so we can
    /// re-tile it even after the patient window steals key/main status.
    @State private var hostWindow: NSWindow?
    var exercise: ExerciseSelectionView.Exercise
    var isTelehealth: Bool = false
    var onBack: () -> Void

    /// Onboarding sub-steps inside the therapist window.
    enum Step {
        case placement
        case calibration
        case session
    }

    var body: some View {
        Group {
            switch step {
            case .placement:
                placementBody.transition(.onboardingStep)
            case .calibration:
                calibrationBody.transition(.onboardingStep)
            case .session:
                TherapistSessionView().transition(.onboardingStep)
            }
        }
        .animation(.onboardingSpring, value: step)
        .background(Group {
            if !isTelehealth {
                WindowAccessor { window in
                    hostWindow = window
                    tileWindow(window, to: .left)
                }
            }
        })
        .onAppear {
            serialManager.calibrationCompleted = false
            serialManager.baselineMV = nil
            serialManager.mvcMV = nil
            if isTelehealth {
                serialManager.networkManager = networkManager
                networkManager.startSender()
            } else {
                openWindow(id: "patient-window")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = hostWindow {
                        tileWindow(window, to: .left)
                    }
                }
            }
        }
    }

    // MARK: - Placement

    /// Routes to the in-clinic or telehealth placement view. Each view owns
    /// its own layout so you can design them independently.
    @ViewBuilder
    private var placementBody: some View {
        Group {
            if isTelehealth {
                TelehealthPlacementView(exercise: .bicepCurl, onContinue: { step = .calibration })
            } else {
                ClinicPlacementView(onContinue: { step = .calibration })
            }
        }
        .navigationTitle("Tandem — Therapist")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    if isTelehealth {
                        networkManager.stopSender()
                        serialManager.networkManager = nil
                    } else {
                        dismissWindow(id: "patient-window")
                    }
                    onBack()
                }) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigation) {
                TandemTitleBar()
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    // MARK: - Calibration

    /// Routes to the in-clinic or telehealth calibration view. Each view
    /// owns its own baseline → MVC substep state, so you can design them
    /// independently.
    @ViewBuilder
    private var calibrationBody: some View {
        Group {
            if isTelehealth {
                TelehealthCalibrationView(
                    onCompleted: finishCalibration,
                    onBack: { step = .placement }
                )
            } else {
                ClinicCalibrationView(
                    onCompleted: finishCalibration,
                    onBack: { step = .placement }
                )
            }
        }
        .navigationTitle("Tandem — Therapist")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { step = .placement }) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigation) {
                TandemTitleBar()
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// Common completion path shared by both calibration variants. The
    /// SerialManager already has the captured baseline/MVC samples by the
    /// time this fires, so we just flip the completion flag, reset reps, and
    /// notify the patient Mac if we're in telehealth.
    private func finishCalibration() {
        serialManager.calibrationCompleted = true
        serialManager.resetReps()
        if isTelehealth { networkManager.sendCalibrationComplete() }
        step = .session
    }

}

func deviceStatusCard(name: String, imageName: String, isConnected: Bool, statusText: String) -> some View {
    HStack(spacing: 12) {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: 48, height: 48)
        Circle()
            .fill(isConnected ? Color.green : Color.red)
            .frame(width: 12, height: 12)
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.headline)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
    .padding(20)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .frame(maxWidth: 480)
}
