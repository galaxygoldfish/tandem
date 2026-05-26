import SwiftUI
import ORSSerial

enum AppFlow {
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

    @ViewBuilder
    private var rootView: some View {
        switch flow {
        case .welcome:
            WelcomeView(onStart: { flow = .connect })
        case .connect:
            HardwareConnectionView(
                onContinue: { flow = .exerciseSelect },
                onBack: { flow = .welcome }
            )
        case .exerciseSelect:
            ExerciseSelectionView(
                onSelect: { flow = .therapist($0) },
                onDeveloper: { flow = .developer },
                onBack: { flow = .connect }
            )
        case .therapist(let exercise):
            TherapistView(
                exercise: exercise,
                onBack: { flow = .exerciseSelect }
            )
        case .developer:
            DevelopmentView()
        }
    }
}
