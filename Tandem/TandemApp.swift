import SwiftUI
import ORSSerial

enum AppFlow: Hashable {
    case welcome
    case connect
    case exerciseSelect
    case therapist(ExerciseSelectionView.Exercise)
    case developer
}

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
                WelcomeView(onStart: { withAnimation(.onboardingSpring) { flow = .connect } })
                    .transition(.onboardingStep)
            case .connect:
                HardwareConnectionView(
                    onContinue: { withAnimation(.onboardingSpring) { flow = .exerciseSelect } },
                    onBack: { withAnimation(.onboardingSpring) { flow = .welcome } }
                )
                .transition(.onboardingStep)
            case .exerciseSelect:
                ExerciseSelectionView(
                    onSelect: { selection in withAnimation(.onboardingSpring) { flow = .therapist(selection) } },
                    onDeveloper: { withAnimation(.onboardingSpring) { flow = .developer } },
                    onBack: { withAnimation(.onboardingSpring) { flow = .connect } }
                )
                .transition(.onboardingStep)
            case .therapist(let exercise):
                TherapistView(
                    exercise: exercise,
                    onBack: { withAnimation(.onboardingSpring) { flow = .exerciseSelect } }
                )
                .transition(.onboardingStep)
            case .developer:
                DevelopmentView()
                    .transition(.onboardingStep)
            }
        }
    }
}
