import SwiftUI
import ORSSerial

@main
struct TandemApp: App {
    
    @StateObject var serialManager = SerialManager()
    
    init() {
        let ports = ORSSerialPortManager.shared().availablePorts
        print("Available ports: \(ports.map { $0.path })")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serialManager)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        
        WindowGroup(id: "console-window") {
            StandaloneConsoleView()
                .environmentObject(serialManager)
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
