import SwiftUI
import ORSSerial

/// Linear navigation state for the main onboarding flow.
///
/// The cases mirror the onboarding stages, ending with either the therapist session
/// for the chosen exercise or the developer dashboard.
enum AppFlow: Hashable {
    case welcome
    case modeSelect
    // Local
    case connect
    case exerciseSelect
    case therapist(ExerciseSelectionView.Exercise)
    // Telehealth
    case telehealthRole
    case telehealthExerciseSelect
    case telehealthLinking(ExerciseSelectionView.Exercise)
    case telehealthTherapist(ExerciseSelectionView.Exercise)
    case telehealthPatient
}

/// App entry point. Hosts three scenes:
/// - the main window (onboarding → therapist/developer session),
/// - the patient window (opened by `TherapistView` when the session starts),
/// - the pop-out console window.
@main
struct TandemApp: App {

    @StateObject var serialManager = SerialManager()
    @StateObject var networkManager = NetworkManager()
    @State private var flow: AppFlow = .welcome

    init() {
        let ports = ORSSerialPortManager.shared().availablePorts
        print("Available ports: \(ports.map { $0.path })")
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(serialManager)
                .environmentObject(networkManager)
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        WindowGroup(id: "patient-window") {
            PatientView()
                .environmentObject(serialManager)
                .environmentObject(networkManager)
                .frame(minWidth: 500, minHeight: 500)
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        WindowGroup(id: "console-window") {
            StandaloneConsoleView()
                .environmentObject(serialManager)
                .frame(minWidth: 400, minHeight: 300)
        }
    }

    private var rootView: some View {
        Group {
            switch flow {
            case .welcome:
                WelcomeView(onStart: { flow = .modeSelect })
                    .transition(.onboardingStep)
            case .modeSelect:
                ModeSelectionView(
                    onLocal: { flow = .connect },
                    onTelehealth: { flow = .telehealthRole },
                    onBack: { flow = .welcome }
                )
                .transition(.onboardingStep)
            case .connect:
                HardwareConnectionView(
                    onContinue: { flow = .exerciseSelect },
                    onBack: { flow = .modeSelect }
                )
                .transition(.onboardingStep)
            case .exerciseSelect:
                ExerciseSelectionView(
                    onSelect: { selection in flow = .therapist(selection) },
                    onBack: { flow = .connect }
                )
                .transition(.onboardingStep)
            case .therapist(let exercise):
                TherapistView(
                    exercise: exercise,
                    onBack: { flow = .exerciseSelect }
                )
                .transition(.onboardingStep)
            case .telehealthRole:
                TelehealthRoleView(
                    onTherapist: { flow = .telehealthExerciseSelect },
                    onPatient: { flow = .telehealthPatient },
                    onBack: { flow = .modeSelect }
                )
                .transition(.onboardingStep)
            case .telehealthExerciseSelect:
                ExerciseSelectionView(
                    onSelect: { selection in flow = .telehealthLinking(selection) },
                    onBack: { flow = .telehealthRole }
                )
                .transition(.onboardingStep)
            case .telehealthLinking(let exercise):
                TelehealthLinkingView(
                    onLinked: { flow = .telehealthTherapist(exercise) },
                    onBack: { flow = .telehealthExerciseSelect }
                )
                .transition(.onboardingStep)
            case .telehealthTherapist(let exercise):
                TherapistView(
                    exercise: exercise,
                    isTelehealth: true,
                    onBack: { flow = .telehealthLinking(exercise) }
                )
                .transition(.onboardingStep)
            case .telehealthPatient:
                TelehealthPatientView(onBack: { flow = .telehealthRole })
                    .transition(.onboardingStep)
            }
        }
        .animation(.onboardingSpring, value: flow)
    }
}
