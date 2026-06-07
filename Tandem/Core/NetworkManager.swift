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
    /// Therapists advertised via Bonjour on the local network (receiver mode).
    @Published var discoveredTherapists: [DiscoveredTherapist] = []
    /// Name advertised to patients when in sender mode. Persists across launches
    /// via `UserDefaults`. Setting this while a listener is live re-publishes
    /// the Bonjour service so patients see the new name immediately.
    @Published var therapistDisplayName: String {
        didSet {
            UserDefaults.standard.set(therapistDisplayName, forKey: Self.therapistNameKey)
            let trimmed = therapistDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let listener, !trimmed.isEmpty {
                listener.service = NWListener.Service(
                    name: trimmed,
                    type: Self.bonjourServiceType
                )
            }
        }
    }

    private static let therapistNameKey = "tandemTherapistName"

    /// Bonjour service type used to discover other Tandem therapists.
    static let bonjourServiceType = "_tandem._tcp"

    /// A therapist found on the local network via Bonjour.
    struct DiscoveredTherapist: Identifiable, Hashable {
        let id: String  // service name doubles as a stable id
        let name: String
        let endpoint: NWEndpoint
    }

    /// Called on main thread when an activation value arrives (receiver mode).
    var onActivationReceived: ((Double) -> Void)?
    /// Called on main thread when the therapist finishes calibration (receiver mode).
    var onCalibrationReceived: (() -> Void)?
    /// Called on main thread when the therapist updates the rep count (receiver mode).
    var onRepCountReceived: ((Int) -> Void)?
    /// Called on main thread when the therapist updates the target reps (receiver mode).
    var onTargetRepsReceived: ((Int) -> Void)?

    private var listener: NWListener?
    private var senderConnections: [NWConnection] = []
    private var receiverConnection: NWConnection?
    private var browser: NWBrowser?
    /// Watchdog timer: if the receiver connection doesn't reach `.ready`
    /// within `connectTimeout` we cancel and restart, since the first attempt
    /// can silently stall while mDNS resolves.
    private var connectWatchdog: DispatchWorkItem?
    private var pendingTherapist: DiscoveredTherapist?
    private var connectAttempt: Int = 0
    private let maxConnectAttempts = 3
    private let connectTimeout: TimeInterval = 3.0

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.therapistNameKey)
        let fallback = Host.current().localizedName ?? "Tandem Therapist"
        self.therapistDisplayName = (stored?.isEmpty == false ? stored : nil) ?? fallback
    }

    // MARK: - Sender (therapist Mac)

    func startSender(port: UInt16 = 9000) {
        // Idempotent: a separate "linking" view starts the sender before
        // TherapistView appears, and TherapistView calls this again. Skip
        // re-creating the listener when one is already running.
        if listener != nil, wirelessMode == .sender {
            return
        }
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
        // Advertise the therapist on the local network so patients can find us.
        let trimmed = therapistDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let advertisedName = trimmed.isEmpty ? "Tandem Therapist" : trimmed
        newListener.service = NWListener.Service(
            name: advertisedName,
            type: Self.bonjourServiceType
        )

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

    func sendRepCount(_ count: Int) {
        guard let data = "REPS:\(count)\n".data(using: .utf8) else { return }
        for conn in senderConnections {
            conn.send(content: data, completion: .idempotent)
        }
    }

    func sendTargetReps(_ count: Int) {
        guard let data = "TARGET:\(count)\n".data(using: .utf8) else { return }
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

    // MARK: - Browse (patient Mac discovers therapists)

    /// Starts a Bonjour browser that surfaces visible therapists into
    /// `discoveredTherapists`. Safe to call repeatedly.
    func startBrowsing() {
        if browser != nil { return }
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: Self.bonjourServiceType,
            domain: nil
        )
        let newBrowser = NWBrowser(for: descriptor, using: NWParameters())
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            let mapped: [DiscoveredTherapist] = results.compactMap { result in
                if case let .service(name, _, _, _) = result.endpoint {
                    return DiscoveredTherapist(id: name, name: name, endpoint: result.endpoint)
                }
                return nil
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self?.discoveredTherapists = mapped
            }
        }
        newBrowser.start(queue: .global(qos: .userInitiated))
        browser = newBrowser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        discoveredTherapists = []
    }

    /// Connects to a therapist that was discovered via Bonjour. Mirrors
    /// `startReceiver(host:port:)` but uses the resolved endpoint directly so
    /// the patient never has to type an IP.
    func connect(to therapist: DiscoveredTherapist) {
        pendingTherapist = therapist
        connectAttempt = 0
        attemptConnect()
    }

    /// Starts (or restarts) the receiver connection to `pendingTherapist`.
    /// We retry up to `maxConnectAttempts` times because the first NWConnection
    /// to a Bonjour endpoint can stall in `.preparing` while mDNS resolves; a
    /// watchdog cancels and retries when that happens so the patient never has
    /// to manually disconnect and re-tap.
    private func attemptConnect() {
        guard let therapist = pendingTherapist else { return }

        // Tear down any leftover connection before starting a new one. Without
        // this, an aborted previous attempt can keep its NWConnection alive in
        // the background and confuse state reporting on the new one.
        receiverConnection?.cancel()
        receiverConnection = nil
        connectWatchdog?.cancel()
        connectWatchdog = nil

        connectAttempt += 1
        wirelessMode = .receiver
        connectionStatus = connectAttempt == 1
            ? "Connecting to \(therapist.name)..."
            : "Retrying \(therapist.name)..."

        // `includePeerToPeer = true` lets Network.framework use the same
        // peer-to-peer discovery path mDNS browsing uses, which dramatically
        // reduces the chance of the first resolution stalling.
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let conn = NWConnection(to: therapist.endpoint, using: params)
        receiverConnection = conn

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                // Ignore late callbacks from a connection we've already replaced.
                guard conn === self.receiverConnection else { return }
                switch state {
                case .ready:
                    self.connectWatchdog?.cancel()
                    self.connectWatchdog = nil
                    self.pendingTherapist = nil
                    self.connectAttempt = 0
                    self.isConnected = true
                    self.connectionStatus = "Connected to \(therapist.name)"
                    // Keep the browser alive through resolution, then drop it
                    // once the TCP connection is up — canceling earlier can
                    // strand the mDNS resolver and stall the first connect.
                    self.stopBrowsing()
                    self.receive(on: conn)
                case .waiting:
                    // `.waiting` means the system gave up on the current
                    // attempt (typically resolution failure). Cancel + retry
                    // immediately instead of letting it sit forever.
                    self.retryConnectIfPossible(reason: "waiting")
                case .failed(let error):
                    self.connectWatchdog?.cancel()
                    self.connectWatchdog = nil
                    if self.connectAttempt < self.maxConnectAttempts {
                        self.retryConnectIfPossible(reason: "failed: \(error.localizedDescription)")
                    } else {
                        self.pendingTherapist = nil
                        self.isConnected = false
                        self.connectionStatus = "Failed: \(error.localizedDescription)"
                        self.stopBrowsing()
                    }
                case .cancelled:
                    // Cancellation can be either ours (retry/teardown) or
                    // user-initiated; the surrounding code paths set status
                    // appropriately, so do nothing here.
                    break
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        scheduleConnectWatchdog()
    }

    private func scheduleConnectWatchdog() {
        connectWatchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // If we're already connected, nothing to do.
            guard !self.isConnected, self.pendingTherapist != nil else { return }
            self.retryConnectIfPossible(reason: "timeout")
        }
        connectWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeout, execute: item)
    }

    private func retryConnectIfPossible(reason: String) {
        guard pendingTherapist != nil else { return }
        guard connectAttempt < maxConnectAttempts else {
            connectionStatus = "Failed to connect (\(reason))"
            isConnected = false
            pendingTherapist = nil
            return
        }
        attemptConnect()
    }

    // MARK: - Receiver (patient Mac)

    func startReceiver(host: String, port: UInt16 = 9000) {
        wirelessMode = .receiver
        connectionStatus = "Connecting to \(host)..."

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
                    self?.connectionStatus = "Connected to \(host)"
                    self?.stopBrowsing()
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
        connectWatchdog?.cancel()
        connectWatchdog = nil
        pendingTherapist = nil
        connectAttempt = 0
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
                    } else if clean.hasPrefix("REPS:"), let count = Int(clean.dropFirst(5)) {
                        DispatchQueue.main.async { self.onRepCountReceived?(count) }
                    } else if clean.hasPrefix("TARGET:"), let count = Int(clean.dropFirst(7)) {
                        DispatchQueue.main.async { self.onTargetRepsReceived?(count) }
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
        browser?.cancel()
    }
}
