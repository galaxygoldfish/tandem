import SwiftUI

/// Therapist's live view after calibration. Shows the EMG waveform with the
/// current strength %, the TENS output waveform, plus toolbar controls for
/// pausing the stream, re-running drift calibration, and aborting the session.
struct TherapistSessionView: View {
    @EnvironmentObject var serialManager: SerialManager
    @State private var isConsoleMinimized = true
    @Environment(\.openWindow) private var openWindow

    var isTelehealth: Bool = false

    var body: some View {
        Group {
            if isTelehealth {
                telehealthLayout
            } else {
                singleColumnLayout
            }
        }
        .background(spacebarAbortShortcut)
        .toolbar {
            ToolbarItemGroup {
                Spacer()
            }
        }
        .navigationTitle("Therapist")
        .navigationSubtitle(connectionSubtitle)
    }

    /// Invisible background handler that registers Space as a global abort
    /// shortcut for this view, regardless of which column layout is active.
    private var spacebarAbortShortcut: some View {
        Button("Abort Space") {
            guard serialManager.isTensEnabled else { return }
            serialManager.hardStop()
        }
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!serialManager.isTensEnabled)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Layouts

    private var singleColumnLayout: some View {
        VStack(spacing: 16) {
            Spacer()
            
            emgFeedbackCard
                .dimmedWhenStimOff(serialManager.isTensEnabled)
            
            tensOutputCard
                .dimmedWhenStimOff(serialManager.isTensEnabled)
            Spacer()
            RepCounterCard(isEditable: true)
                .padding(.horizontal, 20)
                .dimmedWhenStimOff(serialManager.isTensEnabled)
            Spacer()
            Button(action: {
                guard serialManager.isTensEnabled else { return }
                serialManager.hardStop()
            }) {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Text("ABORT")
                            .font(.largeTitle.monospaced().bold())
                    }
                    .frame(maxWidth: .infinity)
                    Text("Spacebar")
                        .font(.body)
                        .opacity(0.5)
                }
                .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(serialManager.isTensEnabled ? Color.red.opacity(0.8) : Color.gray.opacity(0.3))
            .foregroundStyle(serialManager.isTensEnabled ? .white : .secondary)
            .allowsHitTesting(serialManager.isTensEnabled)
            .disabled(!serialManager.isTensEnabled)
            .help("Abort session")
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .animation(.easeInOut(duration: 0.2), value: serialManager.isTensEnabled)
            
            Spacer()
        }
    }

    private var telehealthLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let spacing: CGFloat = 20
                let horizontalPadding: CGFloat = 20
                let available = max(0, geo.size.width - horizontalPadding * 2 - spacing)
                
                HStack(alignment: .top, spacing: spacing) {
                    // Left Column: Split Diagnostic Cards (EMG & TENS)
                    VStack(spacing: 16) {
                        emgFeedbackCard
                            .dimmedWhenStimOff(serialManager.isTensEnabled)
                        
                        tensOutputCard
                            .dimmedWhenStimOff(serialManager.isTensEnabled)
                        
                        Spacer()
                    }
                    .frame(width: available * 0.50)
                    
                    // Right Column: Bio-feedback metrics tracking
                    VStack(spacing: 20) {
                        RepCounterCard(isEditable: true)
                            .frame(maxHeight: .infinity)
                            .dimmedWhenStimOff(serialManager.isTensEnabled)
                    }
                    .frame(width: available * 0.50)
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.vertical, 20)
            
            // Full Width Prominent Abort Dashboard Button
            Button(action: {
                guard serialManager.isTensEnabled else { return }
                serialManager.hardStop()
            }) {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Text("ABORT")
                            .font(.largeTitle.monospaced().bold())
                    }
                    .frame(maxWidth: .infinity)
                    Text("Spacebar")
                        .font(.body)
                        .opacity(0.5)
                }
                .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(serialManager.isTensEnabled ? Color.red.opacity(0.8) : Color.gray.opacity(0.3))
            .foregroundStyle(serialManager.isTensEnabled ? .white : .secondary)
            .allowsHitTesting(serialManager.isTensEnabled)
            .disabled(!serialManager.isTensEnabled)
            .help("Abort session")
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .animation(.easeInOut(duration: 0.2), value: serialManager.isTensEnabled)
        }
    }

    // MARK: - Reusable Modular Subviews

    /// Card 1: Green Patient Intent Tracking Channel
    private var emgFeedbackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your muscle recording")
                .font(.caption.monospaced().bold())
                .foregroundStyle(.green.opacity(0.8))
            
            WaveformView(
                data: serialManager.plotData,
                isRecording: serialManager.isRecording,
                isConnected: serialManager.isConnected
            )
            .frame(height: 120)
            .clipped()
            .animation(.linear(duration: 0.05), value: serialManager.plotData)
            .id(serialManager.isConnected)

            HStack(spacing: 6) {
                Circle()
                    .fill(serialManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(serialManager.isConnected ? "Therapist unit connected" : "Therapist unit disconnected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%% strength", serialManager.normalizedStrength * 100))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 35))
        .padding(.horizontal, isTelehealth ? 0 : 20)
    }

    /// Card 2: Red Hardware Stimulation Channel
    private var tensOutputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Patient stimulation output")
                .font(.caption.monospaced().bold())
                .foregroundStyle(.red.opacity(0.9))
            
            WaveformView(
                data: serialManager.tensPlotData,
                isRecording: serialManager.isRecording,
                isConnected: serialManager.isTensConnected,
                tint: .red
            )
            .frame(height: 120)
            .clipped()
            .animation(.linear(duration: 0.05), value: serialManager.tensPlotData)
            .id(serialManager.isTensConnected)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 35))
        .padding(.horizontal, isTelehealth ? 0 : 20)
    }

    private var abortButton: some View {
        Button(action: {
            guard serialManager.isTensEnabled else { return }
            serialManager.hardStop()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                Text("ABORT")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(serialManager.isTensEnabled ? .red : .gray)
        .allowsHitTesting(serialManager.isTensEnabled)
        .disabled(!serialManager.isTensEnabled)
        .help("Abort session (Space)")
    }

    private var connectionSubtitle: Text {
        let dot = Text(Image(systemName: "circle.fill"))
            .foregroundColor(serialManager.isConnected ? .green : .red)
            .font(.system(size: 8))
        let label = serialManager.isConnected ? "Recording connected" : "Recording disconnected"
        return Text("\(dot)  \(label)")
    }

    private var recalibrateButton: some View {
        Button(action: {
            serialManager.recalibrate()
        }) {
            Image(systemName: "waveform.path.ecg")
        }
        .buttonStyle(.bordered)
        .help("Recalibrate baseline")
    }
}

// MARK: - View Extension

private extension View {
    /// Greys out and disables interaction with the receiver when `enabled` is
    /// false. Used to mute the telemetry cards while session is aborted.
    func dimmedWhenStimOff(_ enabled: Bool) -> some View {
        self
            .opacity(enabled ? 1.0 : 0.4)
            .grayscale(enabled ? 0 : 1)
            .disabled(!enabled)
            .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}
