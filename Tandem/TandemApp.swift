import SwiftUI
import ORSSerial

enum AppFlow {
    case welcome
    case connect
    case main
}

@main
struct TandemApp: App {

    @StateObject var serialManager = SerialManager()
    @State private var flow: AppFlow = .welcome

    init() {
        let ports = ORSSerialPortManager.shared().availablePorts
        print("Available ports: \(ports.map { $0.path })")
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(serialManager)
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        WindowGroup(id: "console-window") {
            StandaloneConsoleView()
                .environmentObject(serialManager)
                .frame(minWidth: 400, minHeight: 300)
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch flow {
        case .welcome:
            WelcomeView(onStart: { flow = .connect })
        case .connect:
            HardwareConnectionView(onContinue: { flow = .main })
        case .main:
            ContentView()
        }
    }
}
