import SwiftUI

struct TensWaveformCard: View {
    @EnvironmentObject var serialManager: SerialManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WaveformView(
                data: serialManager.tensPlotData,
                isRecording: false,
                isConnected: serialManager.isTensConnected,
                tint: .red
            )
            .frame(height: 200)
            .animation(.linear(duration: 0.05), value: serialManager.tensPlotData)
            .id(serialManager.isTensConnected)

            HStack(spacing: 6) {
                Circle()
                    .fill(serialManager.isTensConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(serialManager.isTensConnected ? "Stimulation connected" : "Stimulation not connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }
}
