import SwiftUI

/// Shared card showing the live TENS output waveform in red, with a
/// connection status row and a header chevron to collapse to just the
/// header. The collapsed state is owned by the parent so it can react to
/// it (e.g., resizing a companion video). Used by both Therapist and
/// Patient session views.
struct TensWaveformCard: View {
    @EnvironmentObject var serialManager: SerialManager
    
    // Bind this to the parent view to coordinate the video collapsing
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 0 : 8) {
            header

            if !isCollapsed {
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
                    isCollapsed.toggle()
                }
            }) {
                Image(systemName: isCollapsed ? "menubar.arrow.up.rectangle" : "menubar.rectangle")
            }
            .buttonStyle(.plain)
        }
    }
}
