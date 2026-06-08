import SwiftUI

struct TelehealthPatientView: View {
    @EnvironmentObject var serialManager: SerialManager
    @EnvironmentObject var networkManager: NetworkManager
    var onBack: () -> Void
    
    enum Step: Equatable {
        case connect
        case waiting
        case placement(ExerciseSelectionView.Exercise)
        case session
    }
    @State private var step: Step = .connect
    @State private var connectingDisplay: String = ""
    @State private var showSuccess = false
    @State private var showIPPrompt = false
    @State private var ipInput = ""
    @State private var contentVisible = false
    @State private var waitingVisible = false
    /// Once the patient taps Continue on the placement screen we don't bounce
    /// them back to it if the therapist re-broadcasts the same exercise.
    @State private var placementAcknowledged = false
    
    var body: some View {
        Group {
            switch step {
            case .connect:
                connectBody.transition(.onboardingStep)
            case .waiting:
                waitingBody.transition(.onboardingStep)
            case .placement(let exercise):
                TelehealthPlacementView(
                    exercise: exercise,
                    onContinue: {
                        placementAcknowledged = true
                        withAnimation(.onboardingSpring) {
                            step = .waiting
                        }
                    }
                )
                .transition(.onboardingStep)
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
            if !connected {
                switch step {
                case .waiting, .placement:
                    step = .connect
                    showSuccess = false
                    placementAcknowledged = false
                default: break
                }
            }
        }
    }
    
    private var connectBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.line.dotted.person")
                .font(.system(size: 100))
                .padding(.bottom, 10)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: contentVisible)
            Text("Link to therapist")
                .font(.custom("IBMPlexMono-Medium", size: 40))
                .tracking(-1)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: contentVisible)
            Text("Choose your therapist below to continue")
                .foregroundStyle(.secondary)
                .font(.custom("IBMPlexMono-Regular", size: 20))
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.16), value: contentVisible)
            Spacer()
            VStack(spacing: 12) {
                if networkManager.discoveredTherapists.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.extraLarge)
                    }
                    .padding(.vertical, 24)
                } else {
                    ForEach(networkManager.discoveredTherapists) { therapist in
                        therapistRow(therapist)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.6, anchor: .bottom)),
                                removal: .opacity.combined(with: .scale(scale: 0.8))
                            ))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 480)
            .background(.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(contentVisible ? 1 : 0.6)
            .opacity(contentVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.22), value: contentVisible)
            .animation(.snappy(duration: 0.45, extraBounce: 0.4), value: networkManager.discoveredTherapists.map(\.id))
            Spacer()
            Button {
                ipInput = ""
                showIPPrompt = true
            } label: {
                Text("Try another way")
                    .font(.custom("IBMPlexMono-Regular", size: 15))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
                    .frame(maxWidth: 200)
                    .background(Color.red.opacity(0.2), in: .rect(cornerRadius: 50))
                    .contentShape(.rect(cornerRadius: 50))
            }
            .buttonStyle(.plain)
            .scaleEffect(contentVisible ? 1 : 0.6)
            .opacity(contentVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.28), value: contentVisible)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            networkManager.startBrowsing()
            contentVisible = true
        }
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
            ToolbarItem(placement: .navigation) {
                TandemTitleBar()
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
    
    private func therapistRow(_ therapist: NetworkManager.DiscoveredTherapist) -> some View {
        Button(action: { connect(to: therapist) }) {
            HStack(alignment: .center, spacing: 12) {
                Text(therapist.name)
                    .font(.custom("IBMPlexMono-Regular", size: 30))
                    .tracking(-0.5)
                    .padding(.leading, 20)
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.primary)
                    .padding(10)
                    .font(.system(size: 40))
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 40))
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
            serialManager.calibrationCompleted = true
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
        networkManager.onExerciseReceived = { exercise in
            guard !placementAcknowledged, step == .waiting else { return }
            withAnimation(.onboardingSpring) {
                step = .placement(exercise)
            }
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
                ToolbarItem(placement: .navigation) {
                    TandemTitleBar()
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else {
            VStack(spacing: 24) {
                Spacer()
                ProgressView()
                    .controlSize(.extraLarge)
                    .scaleEffect(waitingVisible ? 1 : 0.6)
                    .opacity(waitingVisible ? 1 : 0)
                    .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: waitingVisible)
                if networkManager.isConnected {
                    Text("Waiting for therapist to calibrate")
                        .font(.custom("IBMPlexMono-Medium", size: 40))
                        .tracking(-1)
                        .multilineTextAlignment(.center)
                        .scaleEffect(waitingVisible ? 1 : 0.6)
                        .opacity(waitingVisible ? 1 : 0)
                        .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: waitingVisible)
                    Text("The session will begin automatically once calibration is complete")
                        .font(.custom("IBMPlexMono-Regular", size: 16))
                        .foregroundStyle(.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .scaleEffect(waitingVisible ? 1 : 0.6)
                        .opacity(waitingVisible ? 1 : 0)
                        .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.16), value: waitingVisible)
                } else {
                    Text("Connecting to \(connectingDisplay.isEmpty ? "therapist" : connectingDisplay)…")
                        .font(.custom("IBMPlexMono-Medium", size: 30))
                        .tracking(-0.5)
                        .scaleEffect(waitingVisible ? 1 : 0.6)
                        .opacity(waitingVisible ? 1 : 0)
                        .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: waitingVisible)
                }
                Spacer()
                Button {
                    networkManager.stopReceiver()
                    placementAcknowledged = false
                    step = .connect
                } label: {
                    Text("Disconnect")
                        .font(.custom("IBMPlexMono-Regular", size: 15))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 22)
                        .frame(maxWidth: 200)
                        .background(Color.black.opacity(0.05), in: .rect(cornerRadius: 50))
                        .contentShape(.rect(cornerRadius: 50))
                }
                .buttonStyle(.plain)
                .scaleEffect(waitingVisible ? 1 : 0.6)
                .opacity(waitingVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.22), value: waitingVisible)
                Spacer()
            }
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .onAppear { waitingVisible = true }
            .onDisappear { waitingVisible = false }
            .navigationTitle("Tandem ")
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    TandemTitleBar()
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}
