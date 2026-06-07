import SwiftUI

/// Telehealth calibration screens (baseline → MVC). The therapist Mac fills
/// the full screen in this mode (no patient window beside it), so this view
/// is laid out with room to breathe.
///
/// Layout however you like — `CalibrationCaptureView` carries the shared
/// countdown / checkmark / SerialManager wiring.
struct TelehealthCalibrationView: View {
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

    private let captureSize: CGFloat = 100

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                switch subStep {
                case .baseline:
                    baselineBody.transition(.onboardingStep)
                case .mvc:
                    mvcBody.transition(.onboardingStep)
                }
            }
            
            TherapistUnitStatusBadge()
                .fixedSize(horizontal: true, vertical: true) // Locks internal dimensions
                .padding(.leading, 30)
                .padding(.bottom, 30)
                .ignoresSafeArea(.all, edges: .bottom) // Prevents the safe area push-down
        }
        .animation(.onboardingSpring, value: subStep)
    }

    // MARK: - Baseline

    private var baselineBody: some View {
        VStack(alignment: .center, spacing: 0) {
            // Equal spring 1: Top window edge clearance
            Spacer(minLength: 20)
            
            // Header Group
            VStack(spacing: 12) {
                Text("Calibrate your baseline")
                    .font(.custom("IBMPlexMono-Medium", size: 40))
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                Text("Relax your arm completely, and keep it relaxed")
                    .font(.custom("IBMPlexMono-Regular", size: 18))
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .scaleEffect(baselineVisible ? 1 : 0.6)
            .opacity(baselineVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: baselineVisible)
            
            // Equal spring 2: Space between headers and data cards
            Spacer(minLength: 24)
            
            // Cards Group
            VStack(spacing: 16) {
                animationCard(resource: "BaselineAnimation", replayDelay: 0)
                waveformCard
            }
            .scaleEffect(baselineVisible ? 1 : 0.6)
            .opacity(baselineVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.16), value: baselineVisible)
            
            // Equal spring 3: Space between cards and action button
            Spacer(minLength: 24)
            
            // Bottom Action Button
            CalibrationCaptureView(mode: .baseline, size: captureSize) {
                subStep = .mvc
            }
            .scaleEffect(baselineVisible ? 1 : 0.6)
            .opacity(baselineVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.28), value: baselineVisible)
            
            // Equal spring 4: Bottom window edge clearance
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .onAppear { baselineVisible = true }
        .onDisappear { baselineVisible = false }
    }

    // MARK: - MVC
    private var mvcBody: some View {
        VStack(alignment: .center, spacing: 0) {
            // Equal spring 1: Pushes down from top window edge
            Spacer(minLength: 20)
            
            // Header Group
            VStack(spacing: 12) {
                Text("Calibrate your maximum strength")
                    .font(.custom("IBMPlexMono-Medium", size: 40))
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                Text("Flex your bicep as hard as you can and hold it there")
                    .font(.custom("IBMPlexMono-Regular", size: 18))
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .scaleEffect(mvcVisible ? 1 : 0.6)
            .opacity(mvcVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: mvcVisible)
            
            // Equal spring 2: Space between title and data cards
            Spacer(minLength: 24)
            
            // Cards Group
            VStack(spacing: 16) {
                animationCard(resource: "MVCAnimation", replayDelay: 3)
                waveformCard
            }
            .scaleEffect(mvcVisible ? 1 : 0.6)
            .opacity(mvcVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.16), value: mvcVisible)
            
            // Equal spring 3: Space between cards and action button
            Spacer(minLength: 24)
            
            // Bottom Action Button
            CalibrationCaptureView(mode: .mvc, size: captureSize) {
                onCompleted()
            }
            .frame(height: captureSize)
            .scaleEffect(mvcVisible ? 1 : 0.6)
            .opacity(mvcVisible ? 1 : 0)
            .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.28), value: mvcVisible)
            
            // Equal spring 4: Pushes up from bottom window edge
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Removed the heavy .padding(.bottom, 60) which was unbalancing the vertical center alignment.
        // The ZStack alignment handles the badge safely now.
        .padding(.horizontal, 40)
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
            .frame(height: 300)
            .frame(maxWidth: 600)
            .padding(20)
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
        .frame(maxWidth: 600)
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 35))
        .animation(.linear(duration: 0.05), value: serialManager.plotData)
        .id(serialManager.isConnected)
    }
}
