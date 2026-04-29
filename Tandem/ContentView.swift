import SwiftUI

struct ContentView: View {
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
            
            Spacer()
            
            if !serialManager.isConsolePoppedOut {
                VStack(spacing: 0) {
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
                    .opacity(0.5)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 15)
                    
                    if !isConsoleMinimized {
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
                .frame(height: isConsoleMinimized ? 40 : nil)
                .frame(maxWidth: .infinity, maxHeight: isConsoleMinimized ? 40 : 300)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.2), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 10)
                .padding(10)
            }
        }
        .toolbar {
            ToolbarItemGroup {
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
                Spacer()
                Button(action: {
                    serialManager.recalibrate()
                }) {
                    Image(systemName: "waveform.path.ecg")
                }
                .buttonStyle(.bordered)
                .help("Recalibrate baseline")
                Spacer()
                Button(action: { serialManager.toggleRecording() }) {
                    HStack(spacing: 8) {
                        Image(systemName: serialManager.isRecording ? "stop.circle.fill" : "record.circle")
                        Text(serialManager.isRecording ? serialManager.recordingTime : "Record")
                            .padding(.trailing, 5)
                    }
                    .foregroundStyle(serialManager.isRecording ? .red : .primary)
                }
                .tint(serialManager.isRecording ? .red : .accentColor)
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Tandem")
        .navigationSubtitle(
            Text(Image(systemName: "circle.fill"))
                .foregroundColor(serialManager.isConnected ? .green : .red)
                .font(.system(size: 8)) +
            Text(" \(serialManager.isConnected ? "Connected" : "Disconnected")")
        )
    }
}
