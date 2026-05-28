import SwiftUI
import ORSSerial

struct PatientView: View {
    @EnvironmentObject var serialManager: SerialManager
    @State private var step: Step = .placement

    enum Step {
        case placement
        case waiting
        case session
    }

    private var tensStatusText: String {
        guard serialManager.isTensConnected else { return "Disconnected" }
        if let path = serialManager.tensPort?.path {
            return "Connected on \(path)"
        }
        return "Connected"
    }

    var body: some View {
        Group {
            switch step {
            case .placement:
                placementBody
            case .waiting:
                waitingBody
            case .session:
                DevelopmentView()
            }
        }
        .background(WindowAccessor { tileWindow($0, to: .right) })
        .onChange(of: serialManager.calibrationCompleted) { _, completed in
            if completed && step == .waiting {
                step = .session
            }
        }
    }

    // MARK: - Placement

    private var placementBody: some View {
        VStack(spacing: 24) {
            Text("Patient")
                .font(.title.bold())
            Text("Please place your electrodes in the specified location now. When you're ready, press continue")
            Spacer()

            Image("BicepTENSElectrode")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 480, maxHeight: 280)
                .padding(20)
                .frame(maxWidth: 480)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            deviceStatusCard(
                name: "TENS Unit",
                imageName: "TensUnit",
                isConnected: serialManager.isTensConnected,
                statusText: tensStatusText
            )

            Button(action: { step = .waiting }) {
                Text("Continue")
                    .frame(minWidth: 120)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem — Patient")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(height: 40)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    // MARK: - Waiting

    private var waitingBody: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Waiting for therapist to calibrate")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem — Patient")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { step = .placement }) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .principal) {
                Color.clear.frame(height: 40)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
