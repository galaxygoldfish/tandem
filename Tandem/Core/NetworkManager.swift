import Foundation
import Network
internal import Combine

/// Handles WiFi TCP streaming of activation values between two Macs.
/// Sender (therapist Mac with Spikerbox) broadcasts normalized activation.
/// Receiver (patient Mac with Arduino) drives the TENS/servo.
class NetworkManager: ObservableObject {

    enum WirelessMode { case none, sender, receiver }

    @Published var wirelessMode: WirelessMode = .none
    @Published var isConnected: Bool = false
    @Published var connectionStatus: String = "Not connected"
    @Published var localIP: String = ""
    @Published var streamPort: UInt16 = 9000

    /// Called on main thread when an activation value arrives (receiver mode).
    var onActivationReceived: ((Double) -> Void)?
    /// Called on main thread when the therapist finishes calibration (receiver mode).
    var onCalibrationReceived: (() -> Void)?

    private var listener: NWListener?
    private var senderConnections: [NWConnection] = []
    private var receiverConnection: NWConnection?

    // MARK: - Sender (therapist Mac)

    func startSender(port: UInt16 = 9000) {
        wirelessMode = .sender
        streamPort = port
        localIP = getLocalIP()
        connectionStatus = "Waiting for receiver..."

        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let newListener = try? NWListener(using: .tcp, on: nwPort) else {
            connectionStatus = "Failed to start server on port \(port)"
            return
        }
        listener = newListener

        newListener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .userInitiated))
            conn.stateUpdateHandler = { [weak self, weak conn] state in
                guard let self, let conn else { return }
                if case .failed = state {
                    DispatchQueue.main.async {
                        self.senderConnections.removeAll { $0 === conn }
                        if self.senderConnections.isEmpty {
                            self.isConnected = false
                            self.connectionStatus = "Waiting for receiver..."
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                self?.senderConnections.append(conn)
                self?.isConnected = true
                self?.connectionStatus = "Receiver connected"
            }
        }

        newListener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                DispatchQueue.main.async {
                    self?.connectionStatus = "Server error: \(error.localizedDescription)"
                }
            }
        }

        newListener.start(queue: .global(qos: .userInitiated))
    }

    func stopSender() {
        listener?.cancel()
        listener = nil
        senderConnections.forEach { $0.cancel() }
        senderConnections.removeAll()
        wirelessMode = .none
        isConnected = false
        connectionStatus = "Not connected"
    }

    func sendCalibrationComplete() {
        guard let data = "CALIBRATED\n".data(using: .utf8) else { return }
        for conn in senderConnections {
            conn.send(content: data, completion: .idempotent)
        }
    }

    /// Called from SerialManager.processNewValue() on the main thread.
    func sendActivation(_ value: Double) {
        guard !senderConnections.isEmpty,
              let data = String(format: "%.4f\n", value).data(using: .utf8) else { return }
        for conn in senderConnections {
            conn.send(content: data, completion: .idempotent)
        }
    }

    // MARK: - Receiver (patient Mac)

    func startReceiver(host: String, port: UInt16 = 9000) {
        wirelessMode = .receiver
        connectionStatus = "Connecting..."

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            connectionStatus = "Invalid port"
            return
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        receiverConnection = conn

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.connectionStatus = "Connected"
                    if let conn = self?.receiverConnection {
                        self?.receive(on: conn)
                    }
                case .failed(let error):
                    self?.isConnected = false
                    self?.connectionStatus = "Failed: \(error.localizedDescription)"
                case .cancelled:
                    self?.isConnected = false
                    self?.connectionStatus = "Disconnected"
                default: break
                }
            }
        }

        conn.start(queue: .global(qos: .userInitiated))
    }

    func stopReceiver() {
        receiverConnection?.cancel()
        receiverConnection = nil
        wirelessMode = .none
        isConnected = false
        connectionStatus = "Not connected"
    }

    private func receive(on connection: NWConnection, buffer: String = "") {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self,
                  let connection,
                  let current = self.receiverConnection,
                  connection === current else { return }

            var newBuffer = buffer
            if let data, let text = String(data: data, encoding: .utf8) {
                newBuffer += text
                var lines = newBuffer.components(separatedBy: "\n")
                newBuffer = lines.removeLast()
                for line in lines {
                    let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean == "CALIBRATED" {
                        DispatchQueue.main.async { self.onCalibrationReceived?() }
                    } else if let value = Double(clean) {
                        DispatchQueue.main.async { self.onActivationReceived?(value) }
                    }
                }
            }

            if error == nil && !isComplete {
                self.receive(on: connection, buffer: newBuffer)
            } else {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.connectionStatus = "Sender disconnected"
                }
            }
        }
    }

    // MARK: - Utilities

    private func getLocalIP() -> String {
        Host.current().addresses.first { addr in
            addr.split(separator: ".").count == 4 &&
            !addr.hasPrefix("127.") &&
            !addr.hasPrefix("169.254.")
        } ?? "Unknown"
    }

    deinit {
        listener?.cancel()
        senderConnections.forEach { $0.cancel() }
        receiverConnection?.cancel()
    }
}
