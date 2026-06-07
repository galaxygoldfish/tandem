import SwiftUI
import ORSSerial

/// Single-device variant of `HardwareConnectionView` used by the telehealth flow.
/// Each side only needs its own unit connected before linking, so we surface
/// just the relevant device.
struct TelehealthHardwareConnectionView: View {
    enum Device {
        case therapist
        case patient

        var title: String {
            switch self {
            case .therapist: return "Plug in your Therapist Unit"
            case .patient: return "Plug in your Patient Unit"
            }
        }

        var deviceName: String {
            switch self {
            case .therapist: return "Therapist unit"
            case .patient: return "Patient unit"
            }
        }

        var imageName: String {
            switch self {
            case .therapist: return "SpikerBox"
            case .patient: return "TensUnit"
            }
        }
    }

    @EnvironmentObject var serialManager: SerialManager
    let device: Device
    var onContinue: () -> Void
    var onBack: () -> Void

    @State private var showCheckmark = false
    @State private var showContinueButton = false
    @State private var contentVisible = false

    private var isConnected: Bool {
        switch device {
        case .therapist: return serialManager.isConnected
        case .patient: return serialManager.isTensConnected
        }
    }

    private var statusText: String {
        switch device {
        case .therapist:
            guard serialManager.isConnected else { return "Disconnected" }
            return "Connected"
        case .patient:
            guard serialManager.isTensConnected else { return "Disconnected" }
            return "Connected"
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(device.title)
                .font(.custom("IBMPlexMono-Medium", size: 40))
                .tracking(-1)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: contentVisible)
            Text("It might take a few seconds to register the device")
                .font(.custom("IBMPlexMono-Regular", size: 16))
                .foregroundStyle(.black.opacity(0.6))
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: contentVisible)
            Spacer()
            Image(device.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 420, maxHeight: 360)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.16), value: contentVisible)
            statusRow
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.22), value: contentVisible)
            Spacer()
            actionArea
                .frame(height: 80)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onChange(of: isConnected) { _, connected in
            handleConnectionChange(connected)
        }
        .onAppear {
            contentVisible = true
            if isConnected { handleConnectionChange(true) }
        }
        .navigationTitle("Tandem")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigation) {
                TandemTitleBar()
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            Text(statusText)
                .font(.custom("IBMPlexMono-Regular", size: 18))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if showContinueButton {
            Button(action: onContinue) {
                Text("Continue")
                    .font(.custom("IBMPlexMono-Medium", size: 22))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 18)
                    .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        } else if showCheckmark {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func handleConnectionChange(_ connected: Bool) {
        guard connected else {
            withAnimation(.snappy(duration: 0.2)) {
                showCheckmark = false
                showContinueButton = false
            }
            return
        }
        withAnimation(.snappy(duration: 0.35, extraBounce: 0.4)) {
            showCheckmark = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.snappy(duration: 0.35, extraBounce: 0.35)) {
                showCheckmark = false
                showContinueButton = true
            }
        }
    }
}
