import SwiftUI

struct PatientSessionView: View {
    @EnvironmentObject var serialManager: SerialManager
    @State private var isConsoleMinimized = true
    @State private var intensity: Double = 6
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            enableStimulationCard
                .padding(.horizontal, 20)
            Spacer()

            intensityCard
                .padding(.horizontal, 20)
                
            Spacer()
            
            exerciseCard
                .padding(.horizontal, 20)
            
            Spacer()
                
            TensWaveformCard()
                .padding(.bottom, 20)

        }
        .toolbar {
            ToolbarItemGroup {
                Spacer()
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
        }
        .navigationTitle("Patient")
        .navigationSubtitle(tensSubtitle)
    }

    private var exerciseCard: some View {
        VStack(alignment: .leading) {
                Text("You're doing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Bicep curl")
                    .font(.title.bold())
                    .padding(.bottom, 10)
                    .padding(.top, 5)
            
            if let videoURL = Bundle.main.url(forResource: "MVCAnimation", withExtension: "mov") {
                LoopingVideoView(url: videoURL, cornerRadius: 10, replayDelay: 3.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 5)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var enableStimulationCard: some View {
        Button(action: { serialManager.isTensEnabled.toggle() }) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable stimulation")
                        .font(.title3.bold())
                    Text("This allows the therapist's movement to be translated to your muscles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enable stimulation", isOn: $serialManager.isTensEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var intensityCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Maximum stimulation strength")
                .font(.title3.bold())
            Text("This is the highest value you will be stimulated at - turn down for less intensity and turn up if you don't see movement")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(
                value: $intensity,
                in: 2...8,
                step: 1,
                label: { Text("Intensity") },
                minimumValueLabel: { Image(systemName: "bolt").padding(10) },
                maximumValueLabel: { Image(systemName: "bolt.fill").padding(10) }
            )
            .labelsHidden()
            .controlSize(.extraLarge)
            .padding(.top, 8)

            HStack {
                ForEach(2...8, id: \.self) { tick in
                    Text("\(tick)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var tensSubtitle: Text {
        let dot = Text(Image(systemName: "circle.fill"))
            .foregroundColor(serialManager.isTensConnected ? .green : .red)
            .font(.system(size: 8))
        let label = serialManager.isTensConnected ? "Stimulation connected" : "Stimulation disconnected"
        return Text("\(dot)  \(label)")
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
