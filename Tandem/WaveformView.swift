import SwiftUI
struct WaveformView: View {
    var data: [Double]
    var isRecording: Bool = false
    var isConnected: Bool = false
    var tint: Color = .green

    let range: Double = 800.0

    var body: some View {

        GeometryReader { geometry in

            Canvas { context, size in
                let stepX = size.width / CGFloat(250 - 1)
                let midY = size.height / 2

                let themeColor: Color = {
                    if !isConnected { return .gray }
                    if isRecording { return .red }
                    return tint
                }()
                
                let gridLinesHorizontal = 15
                let gridLinesVertical = 20
                let gridColor = Color.white.opacity(0.05)
                
                for i in 0...gridLinesHorizontal {
                    let y = CGFloat(i) * (size.height / CGFloat(gridLinesHorizontal))
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    let finalGridColor = abs(y - midY) < 1 ? gridColor.opacity(2.0) : gridColor
                    context.stroke(path, with: .color(finalGridColor), lineWidth: 1)
                }
                
                for i in 0...gridLinesVertical {
                    let x = CGFloat(i) * (size.width / CGFloat(gridLinesVertical))
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(gridColor), lineWidth: 1)
                }

                let points: [CGPoint] = data.indices.map { i in
                    let x = CGFloat(i) * stepX
                    let yOffset = CGFloat(data[i] / range) * midY
                    let y = midY - yOffset
                    return CGPoint(x: x, y: min(max(y, 0), size.height))
                }
                
                var linePath = Path()
                if let firstPoint = points.first {
                    linePath.move(to: firstPoint)
                    for i in 0..<points.count - 1 {
                        let p0 = points[i]
                        let p1 = points[i + 1]
                        let c1 = CGPoint(x: p0.x + (p1.x - p0.x) * 0.5, y: p0.y)
                        let c2 = CGPoint(x: p0.x + (p1.x - p0.x) * 0.5, y: p1.y)
                        linePath.addCurve(to: p1, control1: c1, control2: c2)
                    }
                }
                
                var fillPath = linePath
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()
                
                let gradient = Gradient(colors: [themeColor.opacity(0.2), .clear])
                context.fill(fillPath, with: .linearGradient(gradient,
                                                             startPoint: .zero,
                                                             endPoint: CGPoint(x: 0, y: size.height)))
                
                context.stroke(linePath, with: .color(themeColor.opacity(isConnected ? 0.8 : 0.3)), lineWidth: 3)
            }
        }
    }
}
