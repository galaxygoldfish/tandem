import SwiftUI
import ORSSerial

struct TherapistView: View {
    @EnvironmentObject var serialManager: SerialManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step: Step = .placement
    @State private var baselinePhase: CapturePhase = .idle
    @State private var baselineSecondsRemaining: Int = 3
    @State private var baselineCountdownProgress: Double = 0
    @State private var mvcPhase: CapturePhase = .idle
    @State private var mvcSecondsRemaining: Int = 3
    @State private var mvcCountdownProgress: Double = 0
    var exercise: ExerciseSelectionView.Exercise
    var onBack: () -> Void

    enum Step {
        case placement
        case calibrationBaseline
        case calibrationMVC
        case session
    }

    enum CapturePhase {
        case idle
        case recording
        case completed
    }

    private static let captureDuration: TimeInterval = 3.0

    private var statusText: String {
        guard serialManager.isConnected else { return "Disconnected" }
        if let path = serialManager.serialPort?.path {
            return "Connected on \(path)"
        }
        return "Connected"
    }

    var body: some View {
        Group {
            switch step {
            case .placement:
                placementBody.transition(.onboardingStep)
            case .calibrationBaseline:
                baselineCalibrationBody.transition(.onboardingStep)
            case .calibrationMVC:
                mvcCalibrationBody.transition(.onboardingStep)
            case .session:
                TherapistSessionView().transition(.onboardingStep)
            }
        }
        .animation(.onboardingSpring, value: step)
        .background(WindowAccessor { tileWindow($0, to: .left) })
        .onAppear {
            serialManager.calibrationCompleted = false
            serialManager.baselineMV = nil
            serialManager.mvcMV = nil
            openWindow(id: "patient-window")
        }
    }

    // MARK: - Placement

    private var placementBody: some View {
        VStack(spacing: 24) {
            Text("Therapist")
                .font(.title.bold())
            Text("Please place your electrodes in the specified location now. When you're ready, press continue")
            Spacer()
            electrodePlacementPlaceholder

            deviceStatusCard(
                name: "Muscle SpikerBox (EMG)",
                imageName: "SpikerBox",
                isConnected: serialManager.isConnected,
                statusText: statusText
            )

            VStack(alignment: .leading, spacing: 8) {
                WaveformView(
                    data: serialManager.plotData,
                    isRecording: serialManager.isRecording,
                    isConnected: serialManager.isConnected
                )
                .frame(height: 120)
                .animation(.linear(duration: 0.05), value: serialManager.plotData)
                .id(serialManager.isConnected)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 480)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button(action: { step = .calibrationBaseline }) {
                Text("Continue")
                    .frame(minWidth: 120)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem — Therapist")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    dismissWindow(id: "patient-window")
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

    // MARK: - Calibration

    private var baselineCalibrationBody: some View {
        VStack(spacing: 20) {
            discreteStepGauge(current: 1, total: 2)
            Spacer()
            Text("Calibrate Baseline")
                .font(.title.bold())
            Text("Relax your arm completely, and keep it relaxed")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
            Spacer()
            if let videoURL = Bundle.main.url(forResource: "BaselineAnimation", withExtension: "mov") {
                LoopingVideoView(
                    url: videoURL,
                    cornerRadius: 12,
                    isPlaying: baselinePhase == .idle
                )
                .frame(height: 200)
                .padding(20)
                .frame(maxWidth: 480)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 8) {
                WaveformView(
                    data: serialManager.plotData,
                    isRecording: serialManager.isRecording,
                    isConnected: serialManager.isConnected
                )
                .frame(height: 120)
                .animation(.linear(duration: 0.05), value: serialManager.plotData)
                .id(serialManager.isConnected)

                HStack(spacing: 6) {
                    Circle()
                        .fill(serialManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(serialManager.isConnected ? "Connected" : "Disconnected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 480)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Spacer()
            baselineActionArea
                .frame(height: 130)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { resetBaseline() }
        .navigationTitle("Tandem — Therapist")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    if serialManager.calibrationMode == .baseline {
                        serialManager.toggleBaselineCalibration()
                    }
                    resetBaseline()
                    step = .placement
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

    @ViewBuilder
    private var baselineActionArea: some View {
        switch baselinePhase {
        case .idle:
            Button(action: startBaselineRecording) {
                Text("Start")
                    .frame(minWidth: 120)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

        case .recording:
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: baselineCountdownProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("HOLD")
                        .font(.system(size: 22, weight: .bold))
                    Text("\(baselineSecondsRemaining)")
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: baselineSecondsRemaining)
                }
            }
            .frame(width: 110, height: 110)
            .transition(.scale.combined(with: .opacity))

        case .completed:
            ZStack {
                Circle()
                    .fill(Color.green)
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 110, height: 110)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    private func resetBaseline() {
        baselinePhase = .idle
        baselineSecondsRemaining = 3
        baselineCountdownProgress = 0
    }

    private func startBaselineRecording() {
        Task { @MainActor in
            serialManager.toggleBaselineCalibration()
            baselineSecondsRemaining = 3
            withAnimation(.easeInOut(duration: 0.3)) {
                baselinePhase = .recording
            }
            withAnimation(.linear(duration: Self.captureDuration)) {
                baselineCountdownProgress = 1.0
            }

            try? await Task.sleep(for: .seconds(1))
            baselineSecondsRemaining = 2
            try? await Task.sleep(for: .seconds(1))
            baselineSecondsRemaining = 1
            try? await Task.sleep(for: .seconds(1))
            baselineSecondsRemaining = 0

            if serialManager.calibrationMode == .baseline {
                serialManager.toggleBaselineCalibration()
            }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                baselinePhase = .completed
            }
            try? await Task.sleep(for: .seconds(1))
            step = .calibrationMVC
        }
    }

    private var mvcCalibrationBody: some View {
        VStack(spacing: 20) {
            discreteStepGauge(current: 2, total: 2)
            Spacer()
            Text("Calibrate Maximum Voluntary Contraction")
                .font(.title.bold())
            Text("Flex your bicep as hard as you can and hold it there")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
            Spacer()
            if let videoURL = Bundle.main.url(forResource: "MVCAnimation", withExtension: "mov") {
                LoopingVideoView(
                    url: videoURL,
                    cornerRadius: 12,
                    replayDelay: 3.0,
                    isPlaying: mvcPhase == .idle
                )
                .frame(height: 200)
                .padding(20)
                .frame(maxWidth: 480)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 8) {
                WaveformView(
                    data: serialManager.plotData,
                    isRecording: serialManager.isRecording,
                    isConnected: serialManager.isConnected
                )
                .frame(height: 120)
                .animation(.linear(duration: 0.05), value: serialManager.plotData)
                .id(serialManager.isConnected)

                HStack(spacing: 6) {
                    Circle()
                        .fill(serialManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(serialManager.isConnected ? "Connected" : "Disconnected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 480)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Spacer()
            mvcActionArea
                .frame(height: 130)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { resetMVC() }
        .navigationTitle("Tandem — Therapist")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    if serialManager.calibrationMode == .mvc {
                        serialManager.toggleMVCCalibration()
                    }
                    resetMVC()
                    step = .calibrationBaseline
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

    @ViewBuilder
    private var mvcActionArea: some View {
        switch mvcPhase {
        case .idle:
            Button(action: startMVCRecording) {
                Text("Start")
                    .frame(minWidth: 120)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

        case .recording:
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: mvcCountdownProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("HOLD")
                        .font(.system(size: 22, weight: .bold))
                    Text("\(mvcSecondsRemaining)")
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: mvcSecondsRemaining)
                }
            }
            .frame(width: 110, height: 110)
            .transition(.scale.combined(with: .opacity))

        case .completed:
            ZStack {
                Circle()
                    .fill(Color.green)
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 110, height: 110)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    private func resetMVC() {
        mvcPhase = .idle
        mvcSecondsRemaining = 3
        mvcCountdownProgress = 0
    }

    private func startMVCRecording() {
        Task { @MainActor in
            serialManager.toggleMVCCalibration()
            mvcSecondsRemaining = 3
            withAnimation(.easeInOut(duration: 0.3)) {
                mvcPhase = .recording
            }
            withAnimation(.linear(duration: Self.captureDuration)) {
                mvcCountdownProgress = 1.0
            }

            try? await Task.sleep(for: .seconds(1))
            mvcSecondsRemaining = 2
            try? await Task.sleep(for: .seconds(1))
            mvcSecondsRemaining = 1
            try? await Task.sleep(for: .seconds(1))
            mvcSecondsRemaining = 0

            if serialManager.calibrationMode == .mvc {
                serialManager.toggleMVCCalibration()
            }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                mvcPhase = .completed
            }
            try? await Task.sleep(for: .seconds(1))
            serialManager.calibrationCompleted = true
            step = .session
        }
    }

    private func discreteStepGauge(current: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index < current ? Color.blue : Color.gray.opacity(0.25))
                    .frame(height: 10)
            }
        }
        .frame(maxWidth: 160)
    }

    private var electrodePlacementPlaceholder: some View {
        Image("BicepEMGElectrode")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 480, maxHeight: 280)
            .padding(20)
            .frame(maxWidth: 480)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

func deviceStatusCard(name: String, imageName: String, isConnected: Bool, statusText: String) -> some View {
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
    .padding(20)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .frame(maxWidth: 480)
}
