import SwiftUI

struct TelehealthPatientView: View {
    @EnvironmentObject var serialManager: SerialManager
    @EnvironmentObject var networkManager: NetworkManager
    var onBack: () -> Void

    enum Step { case connect, waiting, session }
    @State private var step: Step = .connect
    @State private var senderIP: String = ""

    var body: some View {
        Group {
            switch step {
            case .connect:
                connectBody.transition(.onboardingStep)
            case .waiting:
                waitingBody.transition(.onboardingStep)
            case .session:
                PatientSessionView().transition(.onboardingStep)
            }
        }
        .animation(.onboardingSpring, value: step)
        .onChange(of: networkManager.isConnected) { _, connected in
            if !connected && step == .waiting {
                step = .connect
            }
        }
    }

    private var connectBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wifi")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Patient — Telehealth")
                .font(.title.bold())
            Text("Enter your therapist's IP address to connect")
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 16) {
                TextField("Therapist's IP (e.g. 192.168.1.5)", text: $senderIP)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                Button("Connect") {
                    networkManager.onActivationReceived = { value in
                        serialManager.receiveRemoteActivation(value)
                    }
                    networkManager.onCalibrationReceived = {
                        withAnimation(.onboardingSpring) {
                            step = .session
                        }
                    }
                    networkManager.startReceiver(host: senderIP)
                    step = .waiting
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(senderIP.isEmpty)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: 480)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem — Telehealth")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .principal) {
                Color.clear.frame(height: 40)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var waitingBody: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            if networkManager.isConnected {
                Text("Waiting for therapist to calibrate")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Text("The session will begin automatically once calibration is complete")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                Text("Connecting to \(senderIP)...")
                    .font(.title2.bold())
            }
            Spacer()
            Button("Disconnect") {
                networkManager.stopReceiver()
                step = .connect
            }
            .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem — Telehealth")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(height: 40)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
