import SwiftUI

/// In-clinic calibration screens (baseline → MVC). The therapist Mac is tiled
/// to the left half of the screen in this mode, so this view is laid out for a
/// narrow split-screen pane.
///
/// Layout however you like — `CalibrationCaptureView` carries the shared
/// countdown / checkmark / SerialManager wiring.
struct ClinicCalibrationView: View {
    @EnvironmentObject private var serialManager: SerialManager
    var onCompleted: () -> Void
    var onBack: () -> Void

    enum SubStep {
        case baseline
        case mvc
    }

    @State private var subStep: SubStep = .baseline
    @State private var baselineVisible = false
    @State private var mvcVisible = false

    var body: some View {
        Group {
            switch subStep {
            case .baseline:
                baselineBody.transition(.onboardingStep)
            case .mvc:
                mvcBody.transition(.onboardingStep)
            }
        }
        .animation(.onboardingSpring, value: subStep)
        .background(WindowAccessor { tileWindow($0, to: .left) })
    }

    // MARK: - Baseline

    private var baselineBody: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Calibrate your baseline")
                .font(.custom("IBMPlexMono-Medium", size: 32))
                .multilineTextAlignment(.center)
                .scaleEffect(baselineVisible ? 1 : 0.6)
                .opacity(baselineVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: baselineVisible)
            Text("Relax your arm completely, and hold")
                .font(.custom("IBMPlexMono-Regular", size: 16))
                .foregroundStyle(.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
                .scaleEffect(baselineVisible ? 1 : 0.6)
                .opacity(baselineVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: baselineVisible)
            Spacer()
            animationCard(resource: "BaselineAnimation", replayDelay: 0)
                .scaleEffect(baselineVisible ? 1 : 0.6)
                .opacity(baselineVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.16), value: baselineVisible)
            waveformCard
                .scaleEffect(baselineVisible ? 1 : 0.6)
                .opacity(baselineVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.22), value: baselineVisible)
            Spacer()
//            TherapistUnitStatusBadge()
//                .padding(20)
//            Spacer()
            CalibrationCaptureView(mode: .baseline) {
                subStep = .mvc
            }
            .scaleEffect(baselineVisible ? 1 : 0.6)
            .opacity(baselineVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.28), value: baselineVisible)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { baselineVisible = true }
        .onDisappear { baselineVisible = false }
    }

    // MARK: - MVC

    private var mvcBody: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Calibrate your maximum strength")
                .font(.custom("IBMPlexMono-Medium", size: 32))
                .multilineTextAlignment(.center)
                .scaleEffect(mvcVisible ? 1 : 0.6)
                .opacity(mvcVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: mvcVisible)
            Text("Flex your bicep as hard as you can and hold")
                .font(.custom("IBMPlexMono-Regular", size: 16))
                .foregroundStyle(.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 550)
                .scaleEffect(mvcVisible ? 1 : 0.6)
                .opacity(mvcVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: mvcVisible)
            Spacer()
            animationCard(resource: "MVCAnimation", replayDelay: 3)
                .scaleEffect(mvcVisible ? 1 : 0.6)
                .opacity(mvcVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.16), value: mvcVisible)
            waveformCard
                .scaleEffect(mvcVisible ? 1 : 0.6)
                .opacity(mvcVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.22), value: mvcVisible)
            Spacer()
            CalibrationCaptureView(mode: .mvc) {
                onCompleted()
            }
            .scaleEffect(mvcVisible ? 1 : 0.6)
            .opacity(mvcVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.28), value: mvcVisible)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { mvcVisible = true }
        .onDisappear { mvcVisible = false }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func animationCard(resource: String, replayDelay: TimeInterval) -> some View {
        if let url = Bundle.main.url(forResource: resource, withExtension: "mov") {
            LoopingVideoView(
                url: url,
                cornerRadius: 35,
                replayDelay: replayDelay
            )
            .frame(height: 220)
            .frame(maxWidth: 480)
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 35))
        }
    }

    private var waveformCard: some View {
        WaveformView(
            data: serialManager.plotData,
            isRecording: serialManager.isRecording,
            isConnected: serialManager.isConnected
        )
        .frame(height: 70)
        .frame(maxWidth: 480)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 35))
        .animation(.linear(duration: 0.05), value: serialManager.plotData)
        .id(serialManager.isConnected)
    }
}
