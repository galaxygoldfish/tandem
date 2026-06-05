import SwiftUI

/// Pop-out window companion for the in-app console panel. Activated from
/// the docked console's expand button so the engineer can keep logs
/// visible on a second display while the main UI stays focused.
struct StandaloneConsoleView: View {
    @EnvironmentObject var serialManager: SerialManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
                .onChange(of: serialManager.logs.count) { _ in
                    if let lastId = serialManager.logs.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Spacer()
                Button(action: {
                    serialManager.isConsolePoppedOut = false
                    dismiss()
                }) {
                    Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                        .frame(width: 20)
                }
                .buttonStyle(.bordered)
                .help("Dock to window")
            }
        }
        .navigationTitle("Console")
        .navigationSubtitle(
            Text(Image(systemName: "circle.fill"))
                .foregroundColor(serialManager.isConnected ? .green : .red)
                .font(.system(size: 8)) +
            Text(" \(serialManager.isConnected ? "Connected" : "Disconnected")")
        )
    }
}
