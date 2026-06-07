import SwiftUI
import ORSSerial

/// Patient window root view. Mirrors the therapist's onboarding rhythm:
/// electrode placement → "waiting for therapist" loader → `PatientSessionView`.
/// Advances to `.session` automatically when the therapist sets
/// `SerialManager.calibrationCompleted = true`.
struct PatientView: View {
    @EnvironmentObject var serialManager: SerialManager
    @EnvironmentObject private var networkManager: NetworkManager
    @State private var step: Step = .placement
    @State private var wirelessEnabled: Bool = false
    @State private var senderIP: String = ""

    /// Onboarding sub-steps inside the patient window.
    enum Step {
        case placement
        case waiting
        case session
    }

    private var tensStatusText: String {
        guard serialManager.isTensConnected else { return "Disconnected" }
        if let path = serialManager.tensPort?.path {
            return "Connected on \(path)"
        }
        return "Connected"
    }

    var body: some View {
        Group {
            switch step {
            case .placement:
                placementBody.transition(.onboardingStep)
            case .waiting:
                waitingBody.transition(.onboardingStep)
            case .session:
                PatientSessionView().transition(.onboardingStep)
            }
        }
        .animation(.onboardingSpring, value: step)
        .background(WindowAccessor { tileWindow($0, to: .right) })
        .onChange(of: serialManager.calibrationCompleted) { _, completed in
            if completed && step == .waiting {
                step = .session
            }
        }
    }

    // MARK: - Placement

    private var placementBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Patient")
                .font(.custom("IBMPlexMono-Medium", size: 32))
                .multilineTextAlignment(.center)
            Text("Place the electrodes on your bicep as shown")
                .font(.custom("IBMPlexMono-Regular", size: 16))
                .foregroundStyle(.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Image("BicepTENSElectrode")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 100)
            Spacer()
            PatientUnitStatusBadge()
                .padding(20)
            Spacer()
            Button(action: { step = .waiting }) {
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
        .navigationTitle("Tandem — Patient")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TandemTitleBar()
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    // MARK: - Waiting

    private var waitingBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Waiting for therapist to calibrate")
                .font(.custom("IBMPlexMono-Medium", size: 30))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            ProgressView()
                .controlSize(.extraLarge)
                .padding(.top, 50)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("")
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
}
