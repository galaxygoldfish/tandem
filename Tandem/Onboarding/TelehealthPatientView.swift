import SwiftUI

struct TelehealthPatientView: View {
    @EnvironmentObject var serialManager: SerialManager
    @EnvironmentObject var networkManager: NetworkManager
    var onBack: () -> Void
    
    enum Step { case connect, waiting, session }
    @State private var step: Step = .connect
    @State private var connectingDisplay: String = ""
    @State private var showSuccess = false
    @State private var showIPPrompt = false
    @State private var ipInput = ""
    
    var body: some View {
        Group {
            switch step {
            case .connect:
                connectBody.transition(.onboardingStep)
            case .waiting:
                waitingBody.transition(.onboardingStep)
            case .session:
                PatientSessionView(isTelehealth: true).transition(.onboardingStep)
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
            Image(systemName: "person.line.dotted.person")
                .font(.system(size: 48))
                .padding(.bottom, 10)
            Text("Link to therapist")
                .font(.title.bold())
            Text("Choose your therapist from the list below to continue")
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 12) {
                if networkManager.discoveredTherapists.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.large)
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
            .background(.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Button("Try another way") {
                ipInput = ""
                showIPPrompt = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { networkManager.startBrowsing() }
        .alert("Enter therapist IP address", isPresented: $showIPPrompt) {
            TextField("192.168.1.5", text: $ipInput)
            Button("Cancel", role: .cancel) { }
            Button("Link") { submitIP() }
        } message: {
            Text("Ask your therapist for the IP address shown at the bottom of their screen.")
        }
        .navigationTitle("Tandem")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    networkManager.stopBrowsing()
                    onBack()
                }) {
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
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "person")
                    .foregroundStyle(.primary)
                    .padding(10)
                    .font(.system(size: 24))
                Text(therapist.name)
                    .font(.title2)
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .font(.system(size: 16))
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
    
    private func submitIP() {
        let host = ipInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        wireUpCallbacks()
        connectingDisplay = host
        networkManager.startReceiver(host: host)
        step = .waiting
    }

    private func connect(to therapist: NetworkManager.DiscoveredTherapist) {
        wireUpCallbacks()
        connectingDisplay = therapist.name
        networkManager.connect(to: therapist)
        step = .waiting
    }

    private func wireUpCallbacks() {
        networkManager.onActivationReceived = { value in
            serialManager.receiveRemoteActivation(value)
        }
        networkManager.onCalibrationReceived = {
            withAnimation(.onboardingSpring) {
                step = .session
            }
        }
        networkManager.onRepCountReceived = { count in
            serialManager.repCount = count
        }
        networkManager.onTargetRepsReceived = { count in
            serialManager.targetReps = count
        }
    }
    
    @ViewBuilder
    private var waitingBody: some View {
        if showSuccess {
            ConnectionSuccessView(
                title: "Connected to \(connectingDisplay.isEmpty ? "therapist" : connectingDisplay)"
            )
            .transition(.opacity)
            .navigationTitle("Tandem")
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
                    Text("Connecting to \(connectingDisplay.isEmpty ? "therapist" : connectingDisplay)…")
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
            .navigationTitle("Tandem ")
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
