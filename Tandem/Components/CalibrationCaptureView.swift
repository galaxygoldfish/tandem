import SwiftUI

/// The "Start → countdown → checkmark" capture widget used by both the
/// in-clinic and telehealth calibration screens. Owns its own phase state and
/// drives `SerialManager` baseline/MVC sampling, so the surrounding layout
/// stays free to differ between the two modes.
struct CalibrationCaptureView: View {
    enum Mode {
        case baseline
        case mvc
    }

    enum Phase {
        case idle
        case recording
        case completed
    }

    let mode: Mode
    var holdSeconds: Int = 3
    /// Base scale for the recording UI: the linear progress bar is drawn at
    /// `size * 2` wide, and HOLD/countdown labels + the completion checkmark
    /// scale off of this. Defaults match the in-clinic narrow-pane layout;
    /// pass a larger value for the telehealth full-screen layout.
    var size: CGFloat = 110
    /// Called once the checkmark has finished animating in. Use this to
    /// advance the surrounding flow's substep.
    var onCompleted: () -> Void

    @EnvironmentObject private var serialManager: SerialManager
    @State private var phase: Phase = .idle
    @State private var secondsRemaining: Int = 3
    @State private var countdownProgress: Double = 0

    var body: some View {
        Group {
            switch phase {
            case .idle:
                Button(action: startRecording) {
                    Text("Start")
                        .font(.custom("IBMPlexMono-Medium", size: 22))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 18)
                        .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))

            case .recording:
                VStack(spacing: size * 0.08) {
                    HStack {
                        Text("HOLD")
                            .font(.custom("IBMPlexMono-Bold", size: size * 0.3))
                        Text("\(secondsRemaining)")
                            .font(.custom("IBMPlexMono-Medium", size: size * 0.3))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: secondsRemaining)
                            .padding(.leading, 5)
                    }
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.25))
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width * countdownProgress)
                        }
                    }
                    .frame(width: size * 2, height: size * 0.3)
                }
                .transition(.scale.combined(with: .opacity))

            case .completed:
                ZStack {
                    Circle()
                        .fill(Color.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: size, height: size)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .onAppear { reset() }
    }

    private func reset() {
        phase = .idle
        secondsRemaining = holdSeconds
        countdownProgress = 0
    }

    private func startRecording() {
        Task { @MainActor in
            toggleCalibration()
            secondsRemaining = holdSeconds
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = .recording
            }
            withAnimation(.linear(duration: TimeInterval(holdSeconds))) {
                countdownProgress = 1.0
            }
            for tick in stride(from: holdSeconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                secondsRemaining = tick
            }
            if isCalibrating { toggleCalibration() }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                phase = .completed
            }
            try? await Task.sleep(for: .seconds(1))
            onCompleted()
        }
    }

    private var isCalibrating: Bool {
        switch mode {
        case .baseline: return serialManager.calibrationMode == .baseline
        case .mvc: return serialManager.calibrationMode == .mvc
        }
    }

    private func toggleCalibration() {
        switch mode {
        case .baseline: serialManager.toggleBaselineCalibration()
        case .mvc: serialManager.toggleMVCCalibration()
        }
    }
}
