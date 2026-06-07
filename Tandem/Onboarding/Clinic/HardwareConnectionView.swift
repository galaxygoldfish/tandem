import SwiftUI
import ORSSerial

/// In-clinic hardware check. Shows the Therapist unit and Patient unit side by
/// side. Each device gets a large image, a status row, and a checkmark when
/// connected. Continue is gated until both have come online.
struct HardwareConnectionView: View {
    @EnvironmentObject var serialManager: SerialManager
    var onContinue: () -> Void
    var onBack: () -> Void

    @State private var contentVisible = false
    @State private var showTherapistCheckmark = false
    @State private var showPatientCheckmark = false
    @State private var showContinueButton = false

    private var bothConnected: Bool {
        serialManager.isConnected && serialManager.isTensConnected
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Plug in your devices")
                .font(.custom("IBMPlexMono-Medium", size: 40))
                .tracking(-1)
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: contentVisible)
            Text("It might take a few seconds to register the devices")
                .font(.custom("IBMPlexMono-Regular", size: 16))
                .foregroundStyle(.black.opacity(0.6))
                .scaleEffect(contentVisible ? 1 : 0.6)
                .opacity(contentVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: contentVisible)
            Spacer()
            HStack(alignment: .top, spacing: 60) {
                deviceColumn(
                    name: "Therapist unit",
                    imageName: "SpikerBox",
                    isConnected: serialManager.isConnected,
                    showCheckmark: showTherapistCheckmark,
                    appearDelay: 0.16
                )
                deviceColumn(
                    name: "Patient unit",
                    imageName: "TensUnit",
                    isConnected: serialManager.isTensConnected,
                    showCheckmark: showPatientCheckmark,
                    appearDelay: 0.22
                )
            }
            Spacer()
            actionArea
                .frame(height: 80)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onChange(of: serialManager.isConnected) { _, connected in
            handleConnectionChange(connected, isTherapist: true)
        }
        .onChange(of: serialManager.isTensConnected) { _, connected in
            handleConnectionChange(connected, isTherapist: false)
        }
        .onAppear {
            contentVisible = true
            if serialManager.isConnected {
                handleConnectionChange(true, isTherapist: true)
            }
            if serialManager.isTensConnected {
                handleConnectionChange(true, isTherapist: false)
            }
            syncContinueButton()
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

    private func deviceColumn(
        name: String,
        imageName: String,
        isConnected: Bool,
        showCheckmark: Bool,
        appearDelay: Double
    ) -> some View {
        VStack(spacing: 16) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 360, maxHeight: 300)
            Text(name)
                .font(.custom("IBMPlexMono-Medium", size: 22))
                .tracking(-0.5)
            statusRow(isConnected: isConnected)
            checkmarkSlot(showCheckmark: showCheckmark)
                .frame(height: 80)
        }
        .scaleEffect(contentVisible ? 1 : 0.6)
        .opacity(contentVisible ? 1 : 0)
        .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(appearDelay), value: contentVisible)
    }

    private func statusRow(isConnected: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            Text(isConnected ? "Connected" : "Disconnected")
                .font(.custom("IBMPlexMono-Regular", size: 18))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func checkmarkSlot(showCheckmark: Bool) -> some View {
        if showCheckmark {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
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
        }
    }

    private func handleConnectionChange(_ connected: Bool, isTherapist: Bool) {
        if connected {
            withAnimation(.snappy(duration: 0.35, extraBounce: 0.4)) {
                if isTherapist {
                    showTherapistCheckmark = true
                } else {
                    showPatientCheckmark = true
                }
            }
        } else {
            withAnimation(.snappy(duration: 0.2)) {
                if isTherapist {
                    showTherapistCheckmark = false
                } else {
                    showPatientCheckmark = false
                }
            }
        }
        syncContinueButton()
    }

    private func syncContinueButton() {
        let shouldShow = bothConnected
        guard shouldShow != showContinueButton else { return }
        let delay = shouldShow ? 0.35 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard bothConnected == shouldShow else { return }
            withAnimation(.snappy(duration: 0.35, extraBounce: 0.4)) {
                showContinueButton = shouldShow
            }
        }
    }
}
