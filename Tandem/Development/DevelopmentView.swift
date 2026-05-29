import SwiftUI

/// Engineer-facing dashboard reached from the "I'm a developer" card on the
/// exercise selection screen. Exposes the full live dashboard (baseline,
/// MVC, strength, TENS) and manual calibration buttons so the pipeline can
/// be exercised without going through onboarding.
struct DevelopmentView: View {
    @EnvironmentObject var serialManager: SerialManager
    @State private var isConsoleMinimized = false
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(spacing: 0) {
            
            Spacer()
            
            WaveformView(
                data: serialManager.plotData,
                isRecording: serialManager.isRecording,
                isConnected: serialManager.isConnected
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.linear(duration: 0.05), value: serialManager.plotData)
            .padding(.horizontal, 20)
            .id(serialManager.isConnected)
            
            VStack(spacing: 12) {
                // MARK: - Calibration & Strength Dashboard
                // Displays live baseline/MVC values, current strength %, and TENS output level.
                dashboardRow
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                
                // MARK: - Calibration & TENS Control Buttons
                // Baseline: capture 3-5 seconds of quiet EMG
                // MVC: capture 2-3 seconds of strong flex
                // TENS: toggle TENS output on/off
                HStack(spacing: 12) {
                    Button(action: { serialManager.toggleBaselineCalibration() }) {
                        Text(serialManager.calibrationMode == .baseline ? "Stop Baseline" : "Baseline")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: { serialManager.toggleMVCCalibration() }) {
                        Text(serialManager.calibrationMode == .mvc ? "Stop MVC" : "MVC")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: { serialManager.toggleTensEnabled() }) {
                        Text(serialManager.isTensEnabled ? "TENS On" : "TENS Off")
                    }
                    .buttonStyle(.bordered)
                    .tint(serialManager.isTensEnabled ? .green : .secondary)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            if !serialManager.isConsolePoppedOut {
                consolePanel
            }
        }
        .toolbar {
            ToolbarItemGroup {
                pauseButton
                Spacer()
                recalibrateButton
                Spacer()
                recordButton
            }
        }
        .navigationTitle("Tandem")
        .navigationSubtitle(connectionSubtitle)
    }

    private var connectionSubtitle: Text {
        let dot = Text(Image(systemName: "circle.fill"))
            .foregroundColor(serialManager.isConnected ? .green : .red)
            .font(.system(size: 8))
        let label = serialManager.isConnected ? "Connected" : "Disconnected"
        return Text("\(dot)  \(label)")
    }

    private var pauseButton: some View {
        Button(action: {
            withAnimation(.spring()) {
                serialManager.isPaused.toggle()
            }
        }) {
            Image(systemName: serialManager.isPaused ? "play.fill" : "pause.fill")
                .frame(width: 20)
        }
        .buttonStyle(.bordered)
        .help(serialManager.isPaused ? "Resume stream" : "Pause stream")
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

    private var recordButton: some View {
        Button(action: { serialManager.toggleRecording() }) {
            let recordText = serialManager.isRecording ? serialManager.recordingTime : "Record"
            HStack(spacing: 8) {
                Image(systemName: serialManager.isRecording ? "stop.circle.fill" : "record.circle")
                Text(recordText)
                    .padding(.trailing, 5)
            }
            .foregroundStyle(serialManager.isRecording ? .red : .primary)
        }
        .tint(serialManager.isRecording ? .red : .accentColor)
        .buttonStyle(.bordered)
    }

    private var consolePanel: some View {
        VStack(spacing: 0) {
            consoleHeader
                .opacity(0.5)
                .padding(.vertical, 10)
                .padding(.horizontal, 15)

            if !isConsoleMinimized {
                consoleLogList
            }
        }
        .frame(height: isConsoleMinimized ? 40 : nil)
        .frame(maxWidth: .infinity, maxHeight: isConsoleMinimized ? 40 : 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.2), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 10)
        .padding(10)
    }

    private var consoleHeader: some View {
        HStack {
            Image(systemName: "apple.terminal")
            Text("Console")

            if isConsoleMinimized, let lastLog = serialManager.logs.last?.text {
                Text("— \(lastLog)")
                    .lineLimit(1)
                    .font(.system(.caption, design: .monospaced))
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isConsoleMinimized.toggle()
                    }
                }) {
                    Image(systemName: isConsoleMinimized ? "menubar.arrow.up.rectangle" : "menubar.rectangle")
                }
                .buttonStyle(.plain)

                Button(action: {
                    openWindow(id: "console-window")
                    serialManager.isConsolePoppedOut = true
                }) {
                    Image(systemName: "arrow.down.left.and.arrow.up.right")
                }
                .buttonStyle(.plain)
                .help("Open console in new window")
            }
        }
    }

    private var consoleLogList: some View {
        ScrollView {
            ScrollViewReader { proxy in
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(serialManager.logs) { entry in
                        Text(entry.text)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 18)
                            .padding(.leading, 15)
                            .id(entry.id)
                    }
                }
                .onChange(of: serialManager.logs.count) { _, _ in
                    if let lastId = serialManager.logs.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var dashboardRow: some View {
        let baselineText = serialManager.baselineMV.map { String(format: "%.3f mV", $0) } ?? "--"
        let mvcText = serialManager.mvcMV.map { String(format: "%.3f mV", $0) } ?? "--"
        let strengthText = String(format: "%.0f%%", serialManager.normalizedStrength * 100)
        let tensText = String(format: "%.3f", serialManager.tensOutput)
        return HStack(spacing: 16) {
            statCell(label: "Baseline", value: baselineText)
            statCell(label: "MVC", value: mvcText)
            Spacer()
            statCell(label: "Strength", value: strengthText)
            statCell(label: "TENS", value: tensText)
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
    }
}
