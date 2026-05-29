import SwiftUI
import ORSSerial

/// Linear navigation state for the main onboarding flow.
///
/// The cases mirror the onboarding stages, ending with either the therapist session
/// for the chosen exercise or the developer dashboard.
enum AppFlow: Hashable {
    case welcome
    case connect
    case exerciseSelect
    case therapist(ExerciseSelectionView.Exercise)
}

/// App entry point. Hosts three scenes:
/// - the main window (onboarding → therapist/developer session),
/// - the patient window (opened by `TherapistView` when the session starts),
/// - the pop-out console window.
@main
struct TandemApp: App {

    @StateObject var serialManager = SerialManager()
    @State private var flow: AppFlow = .welcome

    init() {
        let ports = ORSSerialPortManager.shared().availablePorts
        print("Available ports: \(ports.map { $0.path })")
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(serialManager)
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        WindowGroup(id: "patient-window") {
            PatientView()
                .environmentObject(serialManager)
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
                WelcomeView(onStart: { flow = .connect })
                    .transition(.onboardingStep)
            case .connect:
                HardwareConnectionView(
                    onContinue: { flow = .exerciseSelect },
                    onBack: { flow = .welcome }
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
            }
        }
        .animation(.onboardingSpring, value: flow)
    }
}
