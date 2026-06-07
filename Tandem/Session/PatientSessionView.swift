import SwiftUI

/// Patient's live view after the therapist completes calibration. Lets the
/// patient toggle stimulation on/off (whole card is tappable), pick a maximum
/// stimulation strength via a 0–100 slider that drives `servoIntensity`,
/// watch the bicep-curl reference loop, and see the live TENS waveform.
struct PatientSessionView: View {
    @EnvironmentObject var serialManager: SerialManager
    @State private var isConsoleMinimized = true
    @Environment(\.openWindow) private var openWindow

    var isTelehealth: Bool = false

    // Track whether the waveform card is collapsed to dynamically resize the video
    @State private var isWaveformCollapsed = true
    @State private var isConfigExpanded = false

    /// In telehealth mode the exercise and waveform live in separate columns,
    /// so the video should stay visible regardless of the waveform's state.
    private var keepExerciseExpanded: Bool {
        isTelehealth || isWaveformCollapsed
    }

    var body: some View {
        Group {
            if isTelehealth {
                telehealthLayout
            } else {
                singleColumnLayout
            }
        }
        .background {
            if isTelehealth {
                WindowAccessor { window in maximizeWindow(window) }
            }
        }
        .background(spacebarAbortShortcut)
        .toolbar {
            ToolbarItemGroup {
                Spacer()
            }
        }
        .navigationTitle("Patient")
        .navigationSubtitle(tensSubtitle)
    }

    /// Invisible button that registers Space as a global abort shortcut for
    /// this view, so a hard stop is always one keystroke away regardless of
    /// which layout is on screen.
    private var spacebarAbortShortcut: some View {
        Button("Abort") { serialManager.hardStop() }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!serialManager.isTensEnabled) // Can't abort if it's already off
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private var singleColumnLayout: some View {
        VStack(spacing: 0) {
            Spacer()

            enableStimulationCard
                .padding(.horizontal, 20)
            Spacer()

            intensityCard
                .padding(.horizontal, 20)
                .dimmedWhenStimOff(serialManager.isTensEnabled)

            Spacer()

            RepCounterCard(isEditable: false)
                .padding(.horizontal, 20)
                .dimmedWhenStimOff(serialManager.isTensEnabled) // Muted when stimulation is off

            Spacer()

            exerciseCard
                .padding(.horizontal, 20)
                .dimmedWhenStimOff(serialManager.isTensEnabled)

            Spacer()

            Button(action: { serialManager.hardStop() }) {
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
            .disabled(!serialManager.isTensEnabled) // Hard stop is interactive only when stimulation runs
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
                    VStack(spacing: 20) {
                        enableStimulationCard
                        
                        configurationCard
                            .dimmedWhenStimOff(serialManager.isTensEnabled) // Entire card disabled when off
                        
                        Spacer()
                    }
                    .frame(width: available * 0.40)

                    VStack(spacing: 20) {
                        exerciseCard
                            .frame(maxHeight: .infinity)
                            .dimmedWhenStimOff(serialManager.isTensEnabled)
                        
                        RepCounterCard(isEditable: false)
                            .dimmedWhenStimOff(serialManager.isTensEnabled) // Muted when stimulation is off
                    }
                    .frame(width: available * 0.60, height: nil)
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.vertical, 20)
            
            // Abort Action Button (Changes visually to gray when stimulation is disabled)
            Button(action: { serialManager.hardStop() }) {
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
            .disabled(!serialManager.isTensEnabled) // Hard stop is interactive only when stimulation runs
            .help("Abort session")
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .animation(.easeInOut(duration: 0.2), value: serialManager.isTensEnabled)
        }
    }

    private var abortButton: some View {
        Button(action: { serialManager.hardStop() }) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                Text("ABORT")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(serialManager.isTensEnabled ? .red : .gray)
        .disabled(!serialManager.isTensEnabled)
        .help("Abort session")
    }

    private var exerciseCard: some View {
        VStack(alignment: .leading) {
            Text("You're doing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Bicep curl")
                .font(.title.bold())
                .padding(.bottom, keepExerciseExpanded ? 10 : 0)
                .padding(.top, 5)

            if let videoURL = Bundle.main.url(forResource: "MVCAnimation", withExtension: "mov") {
                LoopingVideoView(
                    url: videoURL,
                    cornerRadius: 35,
                    replayDelay: 3.0,
                    isPlaying: serialManager.isTensEnabled // <-- Ties video freezing directly to switch state
                )
                // Collapses the height to 0 when the waveform is visible
                .frame(
                    maxWidth: .infinity,
                    maxHeight: keepExerciseExpanded ? .infinity : 0
                )
                // Fades out and disables interaction to ensure a clean layout switch
                .opacity(keepExerciseExpanded ? 1 : 0)
                .padding(.horizontal, 5)
                .padding(.bottom, keepExerciseExpanded ? 5 : 0)
                .disabled(!serialManager.isTensEnabled || !keepExerciseExpanded)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 35))
        // Smoothly animates the card resizing when the state changes
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isWaveformCollapsed)
    }

    private var enableStimulationCard: some View {
        Button(action: { serialManager.isTensEnabled.toggle() }) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    // Toggles reading string dynamically based on hardware activation loop
                    Text(serialManager.isTensEnabled ? "Stimulation enabled" : "Stimulation disabled")
                        .font(.custom("IBMPlexMono-Medium", size: 25))
                        .tracking(-1)
                        // Sets white for high contrast on active solid red, black for pale green frame
                        .foregroundStyle(serialManager.isTensEnabled ? .black : .white)
                }
                Spacer()
                Toggle("Enable stimulation", isOn: $serialManager.isTensEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 50)
            .padding(.horizontal, 35)
            .frame(maxWidth: .infinity)
            .background {
                // Background fills with solid diagnostic alert shades based on live states
                if serialManager.isTensEnabled {
                    Color.green.opacity(0.55)
                } else {
                    Color.red.opacity(0.8) // Smooth bright red background color when disabled
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 35))
            .animation(.easeInOut(duration: 0.2), value: serialManager.isTensEnabled)
        }
        .buttonStyle(.plain)
    }

    private var intensityCardContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Maximum stimulation strength")
                .font(.body)
            Text("This is the highest possible value you will be stimulated at")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if serialManager.useOpenEMSstim {
                    Slider(
                        value: Binding(
                            get: { Double(serialManager.emsIntensity) },
                            set: { serialManager.emsIntensity = Int($0) }
                        ),
                        in: 0...100,
                        step: 5,
                        label: { Text("Intensity") },
                        minimumValueLabel: { Image(systemName: "bolt").padding(10) },
                        maximumValueLabel: { Image(systemName: "bolt.fill").padding(10) }
                    )
                } else {
                    Slider(
                        value: Binding(
                            get: { Double(serialManager.servoIntensity) },
                            set: { serialManager.servoIntensity = Int($0) }
                        ),
                        in: 0...100,
                        step: 5,
                        label: { Text("Intensity") },
                        minimumValueLabel: { Image(systemName: "bolt").padding(10) },
                        maximumValueLabel: { Image(systemName: "bolt.fill").padding(10) }
                    )
                }
            }
            .labelsHidden()
            .controlSize(.extraLarge)
            .padding(.top, 8)

            HStack {
                ForEach(0...10, id: \.self) { tick in
                    Text("\(tick * 10)%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 15)
    }

    private var intensityCard: some View {
        intensityCardContent
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 35))
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isConfigExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Configuration")
                        .font(.title3.bold())
                    Spacer()
                    Image(systemName: isConfigExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isConfigExpanded {
                intensityCardContent
                    .padding(.top, 16)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 35))
    }

    private var tensSubtitle: Text {
        let dot = Text(Image(systemName: "circle.fill"))
            .foregroundColor(serialManager.isTensConnected ? .green : .red)
            .font(.system(size: 8))
        let label = serialManager.isTensConnected ? "Patient unit connected" : "Patient unit disconnected"
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
        .clipShape(RoundedRectangle(cornerRadius: 35))
        .overlay(RoundedRectangle(cornerRadius: 35).stroke(.white.opacity(0.2), lineWidth: 1.5))
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

private extension View {
    /// Greys out and disables interaction with the receiver when `enabled` is
    /// false. Used to mute the slider/exercise/TENS waveform cards while
    /// stimulation is off.
    func dimmedWhenStimOff(_ enabled: Bool) -> some View {
        self
            .opacity(enabled ? 1.0 : 0.4)
            .grayscale(enabled ? 0 : 1)
            .disabled(!enabled)
            .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}
