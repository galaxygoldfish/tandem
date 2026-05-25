import SwiftUI
import ORSSerial

struct HardwareConnectionView: View {
    @EnvironmentObject var serialManager: SerialManager
    var onContinue: () -> Void
    var onBack: () -> Void

    // TENS connection isn't implemented yet — hardcoded until it is.
    private let isTensConnected = false

    private var canContinue: Bool {
        serialManager.isConnected
    }

    private var spikerBoxStatusText: String {
        guard serialManager.isConnected else { return "Disconnected" }
        if let path = serialManager.serialPort?.path {
            return "Connected on \(path)"
        }
        return "Connected"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Connect hardware now")
                .font(.title.bold())
            Text("All devices must be connected in order to continue")
            Spacer()
            VStack(spacing: 16) {
                deviceRow(
                    name: "Muscle SpikerBox",
                    imageName: "SpikerBox",
                    isConnected: serialManager.isConnected,
                    statusText: spikerBoxStatusText
                )
                Divider()
                deviceRow(
                    name: "TENS Unit",
                    imageName: "TensUnit",
                    isConnected: isTensConnected,
                    statusText: isTensConnected ? "Connected" : "Disconnected"
                )
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: 420)
            Spacer()
            if canContinue {
                Button(action: onContinue) {
                    Text("Continue")
                        .frame(minWidth: 120)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem")
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

    private func deviceRow(name: String, imageName: String, isConnected: Bool, statusText: String) -> some View {
        HStack(spacing: 12) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
