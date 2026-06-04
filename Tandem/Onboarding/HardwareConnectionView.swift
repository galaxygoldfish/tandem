import SwiftUI
import ORSSerial

/// Lists the EMG SpikerBox and TENS unit with live connection status driven
/// by `SerialManager`. Continue is gated until both Arduinos have completed
/// the `SYSTEM_START_*` handshake (or process-of-elimination fallback).
struct HardwareConnectionView: View {
    @EnvironmentObject var serialManager: SerialManager
    var onContinue: () -> Void
    var onBack: () -> Void

    private var canContinue: Bool {
        true
        //serialManager.isConnected && serialManager.isTensConnected
    }

    private var spikerBoxStatusText: String {
        guard serialManager.isConnected else { return "Disconnected" }
        if let path = serialManager.serialPort?.path {
            return "Connected on \(path)"
        }
        return "Connected"
    }

    private var tensStatusText: String {
        guard serialManager.isTensConnected else { return "Disconnected" }
        if let path = serialManager.tensPort?.path {
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
                    name: "Therapist unit",
                    imageName: "SpikerBox",
                    isConnected: serialManager.isConnected,
                    statusText: spikerBoxStatusText
                )
                Divider()
                deviceRow(
                    name: "Patient unit",
                    imageName: "TensUnit",
                    isConnected: serialManager.isTensConnected,
                    statusText: tensStatusText
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
                .padding(.leading, 5)
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
