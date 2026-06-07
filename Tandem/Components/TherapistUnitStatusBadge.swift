import SwiftUI

/// Compact device status pill: therapist unit image, connection dot, and
/// status text. Lives in the corner of the therapist placement screens so the
/// therapist can verify the EMG unit is online without leaving the page.
struct TherapistUnitStatusBadge: View {
    @EnvironmentObject private var serialManager: SerialManager

    var body: some View {
        HStack(spacing: 0) { // Set spacing to 0 and manage it via paddings cleanly
            Image("SpikerBox")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Therapist Unit")
                    .font(.custom("IBMPlexMono-Medium", size: 16))
                    .foregroundStyle(.black)
                HStack(spacing: 6) {
                    Circle()
                        .fill(serialManager.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(serialManager.isConnected ? "Connected" : "Disconnected")
                        .font(.custom("IBMPlexMono-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 16)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            (serialManager.isConnected ? Color.green : Color.red).opacity(0.2),
            in: .rect(cornerRadius: 20)
        )
        // This ensures the badge container completely ignores layout changes happening in the center of the screen
        .fixedSize(horizontal: true, vertical: true)
    }
}
