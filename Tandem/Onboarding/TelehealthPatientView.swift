import SwiftUI

struct TelehealthPatientView: View {
    @EnvironmentObject var serialManager: SerialManager
    @EnvironmentObject var networkManager: NetworkManager
    var onBack: () -> Void

    enum Step { case connect, waiting, session }
    @State private var step: Step = .connect
    @State private var selectedTherapist: NetworkManager.DiscoveredTherapist?
    @State private var showSuccess = false

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
        .animation(.easeInOut(duration: 0.25), value: showSuccess)
        .onChange(of: networkManager.isConnected) { _, connected in
            if connected && step == .waiting && !showSuccess {
                showSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showSuccess = false
                }
            }
            if !connected && step == .waiting {
                step = .connect
                showSuccess = false
            }
        }
    }

    private var connectBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wifi")
                .font(.system(size: 48))
                .padding(.bottom, 10)
            Text("Link to therapist")
                .font(.title.bold())
            Text("Choose your therapist from the list below to continue")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                if networkManager.discoveredTherapists.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Looking for therapists on this network…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                } else {
                    ForEach(networkManager.discoveredTherapists) { therapist in
                        therapistRow(therapist)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 480)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { networkManager.startBrowsing() }
        .onDisappear { networkManager.stopBrowsing() }
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

    private func therapistRow(_ therapist: NetworkManager.DiscoveredTherapist) -> some View {
        Button(action: { connect(to: therapist) }) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.primary)
                Text(therapist.name)
                    .font(.headline)
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func connect(to therapist: NetworkManager.DiscoveredTherapist) {
        selectedTherapist = therapist
        networkManager.onActivationReceived = { value in
            serialManager.receiveRemoteActivation(value)
        }
        networkManager.onCalibrationReceived = {
            withAnimation(.onboardingSpring) {
                step = .session
            }
        }
        networkManager.connect(to: therapist)
        step = .waiting
    }

    @ViewBuilder
    private var waitingBody: some View {
        if showSuccess {
            ConnectionSuccessView(
                title: "Connected to \(selectedTherapist?.name ?? "therapist")"
            )
            .transition(.opacity)
            .navigationTitle("Tandem — Telehealth")
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(height: 40)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else {
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
                    Text("Connecting to \(selectedTherapist?.name ?? "therapist")…")
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
            .transition(.opacity)
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
}
