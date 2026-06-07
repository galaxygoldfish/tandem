import SwiftUI

/// Renders a real-time running vector line representing biosignal frequencies or telemetry pulses.
struct WaveformView: View {
    var data: [Double]
    var isRecording: Bool
    var isConnected: Bool
    
    // Custom style parameters with safe fallback defaults
    var lineColor: Color = .green
    var showGridLines: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background grid lines loop conditional check
                if showGridLines {
                    gridLinesLayout(in: geo.size)
                }
                
                // The floating waveform vector path
                waveformPath(in: geo.size)
                    .stroke(lineColor, lineWidth: 2.5)
            }
        }
        .background(Color.clear) // Erases hardcoded default card backgrounds inside the canvas layer
    }

    // MARK: - Path Calculators

    @ViewBuilder
    private func gridLinesLayout(in size: CGSize) -> some View {
        Path { path in
            let step = size.height / 5
            for i in 1...4 {
                let y = CGFloat(i) * step
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
    }

    private func waveformPath(in size: CGSize) -> Path {
        var path = Path()
        guard data.count > 1 else {
            // Safe flat fall-through line if device is parsing empty byte packets
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            return path
        }

        let stepX = size.width / CGFloat(data.count - 1)
        
        for index in data.indices {
            let x = CGFloat(index) * stepX
            let y = size.height - (CGFloat(data[index]) * size.height)
            
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

// MARK: - Canvas Preview

#Preview {
    WaveformView(
        data: [0.2, 0.5, 0.3, 0.8, 0.4, 0.6],
        isRecording: true,
        isConnected: true,
        lineColor: .red,        // Matches the updated struct signature
        showGridLines: false    // Matches the updated struct signature
    )
    .frame(width: 300, height: 150)
    .padding()
    .background(.ultraThinMaterial)
}
