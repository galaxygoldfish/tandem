import SwiftUI
import ORSSerial
import CoreText

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
    case telehealthTherapistConnect
    case telehealthPatientConnect
    case telehealthLinking
    case telehealthExerciseSelect
    case telehealthTherapist(ExerciseSelectionView.Exercise)
    case telehealthPatient
    // Debug
    case debugPatientSession
}

/// App entry point. Hosts three scenes:
/// - the main window (onboarding → therapist/developer session),
/// - the patient window (opened by `TherapistView` when the session starts),
/// - the pop-out console window.
@main
struct TandemApp: App {

    @StateObject private var serialManager: SerialManager = {
        let manager = SerialManager()
        manager.setupPort()
        //print("[STIM] OUTPUT MODE: openEMSstim — watch console for activation=… I=… lines")
        return manager
    }()
    @StateObject var networkManager = NetworkManager()
    @State private var flow: AppFlow = .welcome

    init() {
        registerBundledFonts()
        let ports = ORSSerialPortManager.shared().availablePorts
        print("Available ports: \(ports.map { $0.path })")
    }

    /// Registers any .ttf/.otf files bundled with the app so SwiftUI can find
    /// them via `Font.custom(_:size:)` without needing an Info.plist entry.
    private func registerBundledFonts() {
        let extensions = ["ttf", "otf"]
        for ext in extensions {
            guard let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) else { continue }
            for url in urls {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
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

    /// Flow states that share the soft welcome gradient background. Keeping the
    /// image outside the per-screen transition prevents it from sliding during
    /// the welcome ↔ mode-select hand-off.
    private var showsWelcomeBackground: Bool {
        switch flow {
        case .welcome, .modeSelect: return true
        default: return false
        }
    }

    private var rootView: some View {
        ZStack {
            if showsWelcomeBackground {
                Image("WelcomeBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            flowContent
        }
        .animation(.onboardingSpring, value: showsWelcomeBackground)
    }

    private var flowContent: some View {
        Group {
            switch flow {
            case .welcome:
                WelcomeView(
                    onStart: { flow = .modeSelect },
                    onDebugPatientSession: { flow = .debugPatientSession }
                )
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
                    onTherapist: { flow = .telehealthTherapistConnect },
                    onPatient: { flow = .telehealthPatientConnect },
                    onBack: { flow = .modeSelect }
                )
                .transition(.onboardingStep)
            case .telehealthTherapistConnect:
                TelehealthHardwareConnectionView(
                    device: .therapist,
                    onContinue: { flow = .telehealthLinking },
                    onBack: { flow = .telehealthRole }
                )
                .transition(.onboardingStep)
            case .telehealthPatientConnect:
                TelehealthHardwareConnectionView(
                    device: .patient,
                    onContinue: { flow = .telehealthPatient },
                    onBack: { flow = .telehealthRole }
                )
                .transition(.onboardingStep)
            case .telehealthLinking:
                TelehealthLinkingView(
                    onLinked: { flow = .telehealthExerciseSelect },
                    onBack: { flow = .telehealthTherapistConnect }
                )
                .transition(.onboardingStep)
            case .telehealthExerciseSelect:
                ExerciseSelectionView(
                    onSelect: { selection in flow = .telehealthTherapist(selection) },
                    onBack: { flow = .telehealthLinking }
                )
                .transition(.onboardingStep)
            case .telehealthTherapist(let exercise):
                TherapistView(
                    exercise: exercise,
                    isTelehealth: true,
                    onBack: { flow = .telehealthExerciseSelect }
                )
                .transition(.onboardingStep)
                .onAppear { networkManager.sendExercise(exercise) }
            case .telehealthPatient:
                TelehealthPatientView(onBack: { flow = .telehealthPatientConnect })
                    .transition(.onboardingStep)
            case .debugPatientSession:
                TherapistSessionView(isTelehealth: true)
                    .transition(.onboardingStep)
            }
        }
        .animation(.onboardingSpring, value: flow)
    }
}
