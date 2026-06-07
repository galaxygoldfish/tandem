import SwiftUI

/// Telehealth therapist's "waiting for a patient" screen. Advertises this
/// Mac via Bonjour through `NetworkManager.startSender()` and advances as
/// soon as a patient connects.
struct TelehealthLinkingView: View {
    @EnvironmentObject var serialManager: SerialManager
    @EnvironmentObject var networkManager: NetworkManager
    @State private var showSuccess = false
    @State private var contentVisible = false
    var onLinked: () -> Void
    var onBack: () -> Void

    var body: some View {
        Group {
            if showSuccess {
                ConnectionSuccessView(title: "Connected to patient")
                    .transition(.opacity)
            } else {
                waitingBody
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSuccess)
        .onAppear {
            serialManager.networkManager = networkManager
            networkManager.startSender()
        }
        .onChange(of: networkManager.isConnected) { _, connected in
            guard connected, !showSuccess else { return }
            showSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onLinked()
            }
        }
    }

    private var waitingBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.line.dotted.person")
                .font(.system(size: 100))
                .padding(.bottom, 10)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: contentVisible)
            Text("Waiting to link to patient")
                .font(.custom("IBMPlexMono-Medium", size: 40))
                .tracking(-1)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: contentVisible)
            Spacer()
            Text("Patients on this network see you as")
                .font(.custom("IBMPlexMono-Medium", size: 20))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.16), value: contentVisible)
            TextField("Display name", text: $networkManager.therapistDisplayName)
                .textFieldStyle(.plain)
                .font(.custom("IBMPlexMono-Medium", size: 20))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .frame(maxWidth: 360)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.22), value: contentVisible)
            Spacer()
            ProgressView()
                .controlSize(.extraLarge)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.28), value: contentVisible)
            Spacer()
            Text("Your IP: \(networkManager.localIP)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.34), value: contentVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { contentVisible = true }
        .navigationTitle("Tandem")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    networkManager.stopSender()
                    serialManager.networkManager = nil
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
}
