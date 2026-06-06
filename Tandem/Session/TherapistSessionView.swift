import SwiftUI

/// Therapist's live view after calibration. Shows the EMG waveform with the
/// current strength %, the TENS output waveform, plus toolbar controls for
/// pausing the stream, re-running drift calibration, and aborting the session.
struct TherapistSessionView: View {
    @EnvironmentObject var serialManager: SerialManager
    @State private var isConsoleMinimized = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                WaveformView(
                    data: serialManager.plotData,
                    isRecording: serialManager.isRecording,
                    isConnected: serialManager.isConnected
                )
                .frame(height: 200)
                .animation(.linear(duration: 0.05), value: serialManager.plotData)
                .id(serialManager.isConnected)

                HStack(spacing: 6) {
                    Circle()
                        .fill(serialManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(serialManager.isConnected ? "Therapist Connected" : "Therapist Disconnected")
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
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)

            RepCounterCard(isEditable: true)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            if !serialManager.isConsolePoppedOut {
                consolePanel
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Spacer()
                recalibrateButton
                abortButton
            }
        }
        .navigationTitle("Therapist")
        .navigationSubtitle(connectionSubtitle)
    }

    private var abortButton: some View {
        Button(action: { serialManager.hardStop() }) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                Text("ABORT")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .keyboardShortcut(.space, modifiers: [])
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

}
