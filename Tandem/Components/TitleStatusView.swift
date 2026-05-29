import SwiftUI

/// Compact "Tandem · connected" badge for windows without a native title
/// bar (currently the pop-out console).
struct TitleStatusView: View {
    @ObservedObject var serialManager: SerialManager
    
    var body: some View {
        VStack(spacing: 2) {
            Text("Tandem")
                .font(.headline)
            
            HStack(spacing: 4) {
                Circle()
                    .fill(serialManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(serialManager.isConnected ? "Connected" : "Disconnected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
