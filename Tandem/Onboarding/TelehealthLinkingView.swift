import SwiftUI

/// Telehealth therapist's "waiting for a patient" screen. Advertises this
/// Mac via Bonjour through `NetworkManager.startSender()` and advances as
/// soon as a patient connects.
struct TelehealthLinkingView: View {
    @EnvironmentObject var serialManager: SerialManager
    @EnvironmentObject var networkManager: NetworkManager
    var onLinked: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Waiting to link to patient")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("Patients on this network will see this Mac as")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(networkManager.therapistDisplayName)
                .font(.title3.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer()
            Text(networkManager.connectionStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            serialManager.networkManager = networkManager
            networkManager.startSender()
        }
        .onChange(of: networkManager.isConnected) { _, connected in
            if connected {
                onLinked()
            }
        }
        .navigationTitle("Tandem — Telehealth")
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
            ToolbarItem(placement: .principal) {
                Color.clear.frame(height: 40)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
