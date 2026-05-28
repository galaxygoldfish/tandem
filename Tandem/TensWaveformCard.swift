import SwiftUI

struct TensWaveformCard: View {
    @EnvironmentObject var serialManager: SerialManager
    @State private var isMinimized = false

    var body: some View {
        VStack(alignment: .leading, spacing: isMinimized ? 0 : 8) {
            header

            if !isMinimized {
                WaveformView(
                    data: serialManager.tensPlotData,
                    isRecording: false,
                    isConnected: serialManager.isTensConnected,
                    tint: .red
                )
                .frame(height: 200)
                .animation(.linear(duration: 0.05), value: serialManager.tensPlotData)
                .id(serialManager.isTensConnected)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(serialManager.isTensConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(serialManager.isTensConnected ? "Stimulation connected" : "Stimulation not connected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isMinimized.toggle()
                }
            }) {
                Image(systemName: isMinimized ? "menubar.arrow.up.rectangle" : "menubar.rectangle")
            }
            .buttonStyle(.plain)
        }
    }
}
