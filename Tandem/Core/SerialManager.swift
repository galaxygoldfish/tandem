import Foundation
import AppKit
import ORSSerial
import OSLog
internal import Combine
internal import UniformTypeIdentifiers

/// Represents a single log entry displayed in the console.
struct LogEntry: Identifiable {
    let id = UUID()
    let text: String
}

/// SerialManager handles EMG acquisition, signal processing, calibration, and TENS output mapping.
/// 
/// Pipeline:
/// 1. Raw ADC counts → millivolts (using SpikerShield calibration)
/// 2. Dynamic baseline drift correction
/// 3. Envelope extraction (absolute value + moving average)
/// 4. Baseline & MVC calibration (user-specific normalization)
/// 5. Normalized strength [0, 1]
/// 6. Nonlinear mapping to TENS output level
/// 7. Send TENS commands at ~100 ms intervals
///
class SerialManager: NSObject, ObservableObject, ORSSerialPortDelegate {

    // MARK: - UI Publishing
    @Published var logs: [LogEntry] = []
    @Published var isConnected: Bool = false
    @Published var isTensConnected: Bool = false
    @Published var isPaused: Bool = false
    @Published var plotData: [Double] = Array(repeating: 0.0, count: 250)  // EMG waveform display buffer
    @Published var tensPlotData: [Double] = Array(repeating: 0.0, count: 250)  // TENS output display buffer
    @Published var isRecording: Bool = false
    @Published var recordingTime: String = "00:00"
    @Published var isConsolePoppedOut: Bool = false
    /// Set by the therapist when calibration is complete — patient observes this to advance.
    @Published var calibrationCompleted: Bool = false
    
    // MARK: - EMG Processing & Calibration (NEW)
    /// Live normalized strength from EMG (0 = rest, 1 = max contraction).
    @Published var normalizedStrength: Double = 0.0
    /// Mapped TENS output level based on normalized strength [0, 1].
    @Published var tensOutput: Double = 0.0
    /// Whether to actively send TENS commands.
    @Published var isTensEnabled: Bool = true
    /// Captured baseline envelope (mV) — mean of quiet rest period.
    @Published var baselineMV: Double?
    /// Captured MVC envelope (mV) — 95th percentile of strong flex period.
    @Published var mvcMV: Double?
    /// Current calibration mode: none, baseline capture, or MVC capture.
    @Published var calibrationMode: CalibrationMode = .none
    
    // MARK: - Serial Port & Buffers
    /// Set by the therapist view when wireless sender mode is active.
    var networkManager: NetworkManager?

    /// EMG-identified port (broadcasts "VALUE:..." samples).
    var serialPort: ORSSerialPort?
    /// TENS-identified port. No incoming data expected; used only to track connection state.
    var tensPort: ORSSerialPort?
    private enum PortRole { case emg, tens }
    /// Ports that have completed the SYSTEM_START handshake.
    private var portRoles: [String: PortRole] = [:]
    /// Per-port byte buffer used during identification.
    private var pendingBuffers: [String: Data] = [:]
    /// Line-buffer for EMG VALUE: parsing.
    private var emgLineBuffer = Data()
    private var lastUIUpdate = Date()
    private var lastTensSent = Date(timeIntervalSince1970: 0)  // Throttle TENS commands
    
     // MARK: - Signal Processing Constants
    @Published var dynamicBaseline: Double = -1.0  // -1 = uninitialized; set to first sample on arrival
    private var warmupCount: Int = 0
    private var smoothedValue: Double = 0.0  // Exponentially smoothed display value
    private let signalSmoothing: Double = 0.15  // Waveform display smoothing
    private let baselineAlphaFast: Double = 0.05    // Fast convergence for first 500 samples
    private let baselineAlphaSlow: Double = 0.0001  // Slow drift tracking after warmup (τ ≈ 10s at 1kHz)
    private let gainMultiplier: Double = 500.0  // Visual scaling for plot
    
    // MARK: - Calibration & Envelope Buffers
    private var baselineSamples: [Double] = []  // Samples captured during baseline calibration
    private var mvcSamples: [Double] = []  // Samples captured during MVC calibration
    private var envelopeBuffer: [Double] = []  // Short buffer for envelope smoothing (~20 samples)
    private var tensWindowSamples: [Double] = []  // Normalized values accumulated over 500ms window
    private var lastActiveTime: Date = Date(timeIntervalSince1970: 0)
    private var lastActiveValue: Double = 0.0
    private let holdTime: Double = 1.0  // motor only: hold last position 1s after flex ends
    /// EMS fades out over this window after flex ends (not a flat hold at peak).
    private let emsReleaseDuration: Double = 0.55
    
    /// Upper bound (in servo degrees, 0…180) for the TENS command. Driven live
    /// from the "Maximum stimulation strength" slider on the patient view.
    /// When `useOpenEMSstim` is true, this value is capped at 100 and used as the EMS intensity ceiling.
    @Published var maxServoDegrees: Int = 100

    /// When true, output goes to openEMSstim (wchusbserial @ 19200) instead of the motor Arduino.
    var useOpenEMSstim = false

    private var emsReady = false
    private var emsLastIntensity = 0
    private var emsSmoothedLevel = 0.0
    private let emsRampStepUp = 1
    private let emsRampStepDown = 2
    private let emsPulseDurationMs = 150
    private let emsIntensitySmoothing = 0.12
    private let emsOutputCurveExp = 1.4
    private let sensoryThreshold = 0.3

    private var sendInterval: TimeInterval { useOpenEMSstim ? 0.1 : 0.5 }

    /// Calibration mode enum: tracks whether we're capturing baseline or MVC.
    enum CalibrationMode {
        case none
        case baseline
        case mvc
    }
    
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var recordedData: [(timestamp: Int64, signal: Double, normalized: Double, tens: Double)] = []

    /// Discover any already-attached USB serial ports and subscribe to
    /// hot-plug events so future Arduinos are picked up automatically.
    override init() {
        super.init()

        setupPort()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(portsChanged(_:)), name: NSNotification.Name.ORSSerialPortsWereConnected, object: nil)
        nc.addObserver(self, selector: #selector(portsChanged(_:)), name: NSNotification.Name.ORSSerialPortsWereDisconnected, object: nil)
    }

    /// Resets baseline tracking and clears the plot buffer.
    /// Used by the toolbar "Recalibrate" button to recover from drift.
    func recalibrate() {
        dynamicBaseline = -1.0
        warmupCount = 0
        envelopeBuffer.removeAll()
        tensWindowSamples.removeAll()
        emsLastIntensity = 0
        emsSmoothedLevel = 0.0
        DispatchQueue.main.async {
            self.logs.append(LogEntry(text: "RECALIBRATED BASELINE"))
            self.plotData = Array(repeating: 0.0, count: 250)
            self.normalizedStrength = 0.0
            self.tensOutput = 0.0
        }
    }

    /// Start or stop baseline calibration. During baseline, quiet EMG samples are collected for 3-5 seconds.
    func toggleBaselineCalibration() {
        if calibrationMode == .baseline {
            stopCalibration()
        } else {
            calibrationMode = .baseline
            baselineSamples.removeAll()
            DispatchQueue.main.async {
                self.logs.append(LogEntry(text: "BASELINE CALIBRATION STARTED"))
            }
        }
    }

    /// Start or stop MVC (maximum voluntary contraction) calibration. During MVC, strong flex samples are collected for 2-3 seconds.
    func toggleMVCCalibration() {
        if calibrationMode == .mvc {
            stopCalibration()
        } else {
            calibrationMode = .mvc
            mvcSamples.removeAll()
            DispatchQueue.main.async {
                self.logs.append(LogEntry(text: "MVC CALIBRATION STARTED"))
            }
        }
    }

    /// Toggle TENS output on/off. When enabled, normalized EMG is mapped to TENS commands sent every ~100 ms.
    func toggleTensEnabled() {
        isTensEnabled.toggle()
        DispatchQueue.main.async {
            self.logs.append(LogEntry(text: self.isTensEnabled ? "TENS OUTPUT ENABLED" : "TENS OUTPUT DISABLED"))
        }
    }

    /// Finalize calibration by computing baseline mean or MVC 95th percentile.
    private func stopCalibration() {
        switch calibrationMode {
        case .baseline:
            if !baselineSamples.isEmpty {
                baselineMV = baselineSamples.reduce(0, +) / Double(baselineSamples.count)
                DispatchQueue.main.async {
                    self.logs.append(LogEntry(text: String(format: "BASELINE SET: %.4f mV", self.baselineMV ?? 0.0)))
                }
            } else {
                DispatchQueue.main.async {
                    self.logs.append(LogEntry(text: "BASELINE CAPTURE FAILED: no samples"))
                }
            }
        case .mvc:
            if !mvcSamples.isEmpty {
                mvcMV = percentile(values: mvcSamples, percentile: 95)
                DispatchQueue.main.async {
                    self.logs.append(LogEntry(text: String(format: "MVC SET: %.4f mV", self.mvcMV ?? 0.0)))
                }
            } else {
                DispatchQueue.main.async {
                    self.logs.append(LogEntry(text: "MVC CAPTURE FAILED: no samples"))
                }
            }
        case .none:
            break
        }
        calibrationMode = .none
    }

    /// Compute the Pth percentile of a sorted array using linear interpolation.
    /// Used for MVC: we take 95th percentile instead of raw max to reduce noise sensitivity.
    private func percentile(values: [Double], percentile: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0.0 }
        let rank = percentile / 100.0 * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        if lower == upper { return sorted[lower] }
        let weight = rank - Double(lower)
        return sorted[lower] * (1.0 - weight) + sorted[upper] * weight
    }

    /// Map normalized activation to output level with threshold + soft curve (EMS path).
    private func mapToEMSOutputLevel(_ normalized: Double) -> Double {
        guard normalized >= sensoryThreshold else { return 0.0 }
        let safe = max(0.0, min(1.0, normalized))
        let span = 1.0 - sensoryThreshold
        let t = (safe - sensoryThreshold) / span
        return pow(t, emsOutputCurveExp)
    }

    /// Map normalized strength [0, 1] to motor/TENS display level (linear above threshold).
    private func mapToTensLevel(_ normalized: Double) -> Double {
        guard normalized >= sensoryThreshold else { return 0.0 }
        return max(0.0, min(1.0, normalized))
    }

    /// Motor holds peak briefly after flex; EMS eases out over `emsReleaseDuration`.
    private func activationForOutput(_ avgNormalized: Double, now: Date) -> Double {
        if avgNormalized >= sensoryThreshold {
            lastActiveTime = now
            lastActiveValue = avgNormalized
            return avgNormalized
        }
        if useOpenEMSstim {
            let elapsed = now.timeIntervalSince(lastActiveTime)
            guard elapsed < emsReleaseDuration, lastActiveValue > 0 else { return 0.0 }
            let t = elapsed / emsReleaseDuration
            let fade = (1.0 - t) * (1.0 - t)
            return lastActiveValue * fade
        }
        let inHold = now.timeIntervalSince(lastActiveTime) < holdTime
        return inHold ? lastActiveValue : 0.0
    }

    /// Called by the patient Mac when receiving activation values wirelessly.
    /// Applies hold time logic and drives the TENS/servo, mirroring processNewValue's send path.
    func receiveRemoteActivation(_ value: Double) {
        // Abort gates remote drive too: if stimulation is off we silently drop
        // network-supplied activations so the servo stays parked at 0°.
        guard isTensEnabled else { return }
        let now = Date()
        let sendValue = activationForOutput(value, now: now)
        let tensLevel = useOpenEMSstim ? mapToEMSOutputLevel(sendValue) : mapToTensLevel(sendValue)
        sendStimulationOutput(activation: sendValue, displayLevel: tensLevel)
        normalizedStrength = value
        tensOutput = tensLevel
    }

    /// Emergency stop: cuts new stimulation commands and parks the servo at
    /// 0° right now. Sends the zero command three times in rapid succession so
    /// it's robust to a dropped serial packet, and clears the hold-time state
    /// so the next legitimate activation has to re-trigger from rest.
    func hardStop() {
        isTensEnabled = false
        tensWindowSamples.removeAll()
        lastActiveValue = 0.0
        lastActiveTime = Date(timeIntervalSince1970: 0)
        normalizedStrength = 0.0
        tensOutput = 0.0
        emsLastIntensity = 0
        emsSmoothedLevel = 0.0
        // Send the zero command synchronously on the port, bypassing the
        // periodic throttle in processNewValue / receiveRemoteActivation.
        if useOpenEMSstim {
            let zero = "C0I0T\(emsPulseDurationMs)G"
            if let data = zero.data(using: .utf8) {
                for _ in 0..<3 { tensPort?.send(data) }
            }
        } else {
            let zero = "0\n".data(using: .utf8) ?? Data()
            for _ in 0..<3 { tensPort?.send(zero) }
        }
        DispatchQueue.main.async {
            let msg = self.useOpenEMSstim ? "ABORT — EMS stopped" : "ABORT — servo parked at 0°"
            self.logStim(msg)
        }
    }

    /// Build openEMSstim command from raw activation [0, 1] — mirrors test_openEMSstim.py.
    private func emsCommand(for activation: Double) -> String? {
        let alpha: Double
        if activation < emsSmoothedLevel {
            alpha = min(1.0, emsIntensitySmoothing * 2.8)
        } else {
            alpha = emsIntensitySmoothing
        }
        emsSmoothedLevel += (activation - emsSmoothedLevel) * alpha

        if emsSmoothedLevel < 0.001 && emsLastIntensity == 0 { return nil }

        let curved = mapToEMSOutputLevel(emsSmoothedLevel)
        let ceiling = min(maxServoDegrees, 100)
        let raw = Int(curved * Double(ceiling) + 0.5)
        let target = max(0, min(raw, ceiling))
        let ramped: Int
        if target > emsLastIntensity {
            ramped = min(target, emsLastIntensity + emsRampStepUp)
        } else {
            ramped = max(target, emsLastIntensity - emsRampStepDown)
        }
        emsLastIntensity = ramped
        return "C0I\(ramped)T\(emsPulseDurationMs)G"
    }

    /// Route normalized activation to motor or openEMSstim output.
    private func sendStimulationOutput(activation: Double, displayLevel: Double) {
        guard isTensConnected else { return }
        if useOpenEMSstim {
            guard emsReady else { return }
            let pct = Int((activation * 100).rounded())
            let command = emsCommand(for: activation)
            if let command, let data = command.data(using: .utf8) {
                logStim("activation=\(pct)%  I=\(emsLastIntensity)  → \(command)")
                tensPort?.send(data)
            } else {
                logStim("activation=\(pct)%  → off")
            }
        } else {
            let degrees = Int(displayLevel * Double(maxServoDegrees))
            let command = "\(degrees)\n"
            logStim("activation=\(Int((activation * 100).rounded()))%  → \(degrees)°")
            if let data = command.data(using: .utf8) {
                tensPort?.send(data)
            }
        }
    }

    /// Console + in-app log line for stimulation debugging (also prints to Xcode console).
    private func logStim(_ text: String) {
        Logger.serial.info("\(text)")
        print("[STIM] \(text)")
        DispatchQueue.main.async {
            self.logs.append(LogEntry(text: text))
            if self.logs.count > 500 { self.logs.removeFirst() }
        }
    }

    /// Notification handler for USB connect/disconnect events.
    /// Delays the rescan so the OS has time to enumerate the new port.
    @objc func portsChanged(_ notification: Notification) {
        // Small delay allows the OS to fully register the port before we grab it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupPort()
        }
    }

    /// Opens any USB serial port we haven't already identified, so it can be
    /// classified as the EMG or TENS Arduino by its `SYSTEM_START_*` handshake.
    func setupPort() {
        let availablePorts = ORSSerialPortManager.shared().availablePorts
        let allPaths = availablePorts.map(\.path).joined(separator: ", ")
        Logger.serial.info("Available serial ports: \(allPaths)")

        for port in availablePorts {
            let path = port.path.lowercased()
            guard portRoles[port.path] == nil else { continue }

            if useOpenEMSstim, path.contains("usbserial") || path.contains("wchusbserial") {
                port.baudRate = 19200
                port.delegate = self
                port.open()
                portRoles[path] = .tens
                tensPort = port
                emsReady = false
                isTensConnected = false
                Logger.serial.info("Opening openEMSstim port: \(port.path)")
                DispatchQueue.main.async {
                    self.logs.append(LogEntry(text: "OPENING EMS: \(port.path) (10s init)"))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    guard let self, self.tensPort?.path == port.path else { return }
                    self.emsReady = true
                    self.isTensConnected = true
                    let ceiling = min(self.maxServoDegrees, 100)
                    self.logStim("EMS CONNECTED: \(port.path) (ceiling=\(ceiling), interval=\(self.sendInterval)s)")
                }
            } else if path.contains("usb"), pendingBuffers[port.path] == nil {
                port.baudRate = 115200
                port.delegate = self
                pendingBuffers[port.path] = Data()
                port.open()
                Logger.serial.info("Opening port for identification: \(port.path)")
                DispatchQueue.main.async {
                    self.logs.append(LogEntry(text: "OPENING: \(port.path)"))
                }
            }
        }
    }
    
    /// Start or stop recording the EMG/TENS stream to disk.
    func toggleRecording() {
        if isRecording { stopRecording() }
        else { startRecording() }
    }


    private func startRecording() {
        recordedData.removeAll()
        recordingStartTime = Date()
        isRecording = true
        DispatchQueue.main.async {
            self.logs.append(LogEntry(text: "RECORDING STARTED @ \(Date().formatted(date: .omitted, time: .standard))"))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateRecordingTime()
        }
    }

    private func stopRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil
        DispatchQueue.main.async {
            self.logs.append(LogEntry(text: "RECORDING ENDED @ \(Date().formatted(date: .omitted, time: .standard))"))
        }
        saveCSV()
        recordingTime = "00:00"
    }

    private func updateRecordingTime() {
        // If paused, don't increment the clock
        if isPaused { return }
        
        guard let start = recordingStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        
        DispatchQueue.main.async {
            self.recordingTime = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    // Conversion factor for SpikerShield (5V ref, 10-bit, 600x gain)
    private let toMillivolts: Double = 0.00815

    private func processNewValue(_ value: Double) {
        if dynamicBaseline < 0 { dynamicBaseline = value }
        warmupCount += 1
        let alpha = warmupCount < 500 ? baselineAlphaFast : baselineAlphaSlow
        dynamicBaseline = (value * alpha) + (dynamicBaseline * (1 - alpha))

        if isPaused { return }

        // Calculate the raw difference from baseline
        let centeredRaw = value - dynamicBaseline

        // Convert that difference to millivolts
        let centeredMV = centeredRaw * toMillivolts

        // Take absolute value (rectify) the centered EMG.
        let absMV = abs(centeredMV)

        // Maintain a short envelope buffer (~20 samples) for smoothing.
        envelopeBuffer.append(absMV)
        if envelopeBuffer.count > 20 { envelopeBuffer.removeFirst() }
        let envelope = envelopeBuffer.reduce(0, +) / Double(envelopeBuffer.count)

        // During calibration, collect envelope samples for baseline or MVC computation.
        if calibrationMode == .baseline {
            baselineSamples.append(envelope)
        } else if calibrationMode == .mvc {
            mvcSamples.append(envelope)
        }

        // Scale for visual display (exponential smoothing for plot).
        let amplified = envelope * (gainMultiplier * 20)
        smoothedValue = (amplified * signalSmoothing) + (smoothedValue * (1 - signalSmoothing))
        
        // Compute normalized strength [0, 1] and map to TENS level.
        let normalized = computeNormalizedStrength(envelope)
        let tensLevel = useOpenEMSstim
            ? mapToEMSOutputLevel(mapToTensLevel(normalized))
            : mapToTensLevel(normalized)

        if isRecording, let start = recordingStartTime {
            let ms = Int64(Date().timeIntervalSince(start) * 1000)
            recordedData.append((timestamp: ms, signal: absMV, normalized: normalized, tens: tensLevel))
        }

        // Accumulate normalized values and send averaged command every 500ms.
        tensWindowSamples.append(normalized)
        if isTensEnabled, Date().timeIntervalSince(lastTensSent) > sendInterval {
            lastTensSent = Date()
            let avgNormalized = tensWindowSamples.reduce(0, +) / Double(tensWindowSamples.count)
            tensWindowSamples.removeAll()
            let sendValue = activationForOutput(avgNormalized, now: Date())
            let displayLevel = useOpenEMSstim
                ? mapToEMSOutputLevel(mapToTensLevel(sendValue))
                : mapToTensLevel(sendValue)
            sendStimulationOutput(activation: sendValue, displayLevel: displayLevel)
            networkManager?.sendActivation(avgNormalized)
        }

        // Update UI with latest values.
        DispatchQueue.main.async {
            self.plotData.append(self.smoothedValue)
            if self.plotData.count > 250 { self.plotData.removeFirst() }
            // Scale TENS [0, 1] to the same display range used by the EMG waveform.
            self.tensPlotData.append(tensLevel * 400)
            if self.tensPlotData.count > 250 { self.tensPlotData.removeFirst() }
            self.normalizedStrength = normalized
            self.tensOutput = tensLevel
        }
    }

    /// Compute normalized EMG strength as: (envelope - baseline) / (mvc - baseline), clamped to [0, 1].
    /// Returns 0 if calibration is not complete.
    private func computeNormalizedStrength(_ envelope: Double) -> Double {
        guard let baseline = baselineMV, let mvc = mvcMV, mvc > baseline else {
            return 0.0  // Not yet calibrated.
        }
        return max(0.0, min(1.0, (envelope - baseline) / (mvc - baseline)))
    }

    private func saveCSV() {
        if recordedData.isEmpty { return }
        var csvString = "timestamp_ms,signal_mV,normalized_strength,tens_level\n"
        for entry in recordedData {
            csvString += "\(entry.timestamp),\(entry.signal),\(entry.normalized),\(entry.tens)\n"
        }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "tandem_capture_\(Int(Date().timeIntervalSince1970)).csv"
        savePanel.message = "Save EMG recording data as a CSV file."
        savePanel.prompt = "Save"

        DispatchQueue.main.async {
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                savePanel.beginSheetModal(for: window) { response in
                    if response == .OK, let url = savePanel.url {
                        try? csvString.write(to: url, atomically: true, encoding: .utf8)
                        self.logs.append(LogEntry(text: "Recording saved to: \(url.path)"))
                    } else {
                        self.logs.append(LogEntry(text: "Recording save canceled"))
                    }
                }
            } else {
                let response = savePanel.runModal()
                if response == .OK, let url = savePanel.url {
                    try? csvString.write(to: url, atomically: true, encoding: .utf8)
                    self.logs.append(LogEntry(text: "Recording saved to: \(url.path)"))
                } else {
                    self.logs.append(LogEntry(text: "Recording save canceled"))
                }
            }
        }
    }
    
    private let rawToMillivolts: Double = (5.0 / 1023.0 / 600.0) * 1000.0 // approx 0.00815
    
    func serialPort(_ port: ORSSerialPort, didReceive data: Data) {
        if let role = portRoles[port.path] {
            switch role {
            case .emg:
                processEMGData(data)
            case .tens:
                break  // TENS arduino has no incoming stream to parse yet.
            }
        } else {
            identifyPort(port, incoming: data)
        }
    }

    private func identifyPort(_ port: ORSSerialPort, incoming data: Data) {
        var buffer = pendingBuffers[port.path] ?? Data()
        buffer.append(data)
        guard let text = String(data: buffer, encoding: .utf8) else {
            pendingBuffers[port.path] = buffer
            return
        }

        if text.contains("SYSTEM_START_EMG") {
            assignEMG(port, leftoverBuffer: dropEverythingThrough("SYSTEM_START_EMG", in: text))
        } else if !useOpenEMSstim, text.contains("SYSTEM_START_TENS") {
            portRoles[port.path] = .tens
            pendingBuffers.removeValue(forKey: port.path)
            DispatchQueue.main.async {
                self.tensPort = port
                self.isTensConnected = true
                self.logs.append(LogEntry(text: "TENS CONNECTED: \(port.path)"))
            }
        } else if text.contains("VALUE:") {
            // Fallback: the EMG arduino was already past setup() when we attached, so we
            // missed SYSTEM_START_EMG. Streaming VALUE: lines are enough to identify it.
            assignEMG(port, leftoverBuffer: buffer)
        } else {
            // Cap the identification buffer so a misbehaving device can't grow it unbounded.
            if buffer.count > 4096 {
                buffer.removeFirst(buffer.count - 4096)
            }
            pendingBuffers[port.path] = buffer
        }
    }

    private func assignEMG(_ port: ORSSerialPort, leftoverBuffer: Data) {
        portRoles[port.path] = .emg
        pendingBuffers.removeValue(forKey: port.path)
        emgLineBuffer = leftoverBuffer
        DispatchQueue.main.async {
            self.serialPort = port
            self.isConnected = true
            self.logStim("EMG CONNECTED: \(port.path)")
        }
        // The TENS arduino prints SYSTEM_START_TENS once and then nothing. If we missed
        // that line (e.g., the board didn't auto-reset on port open), it would stay pending
        // forever. Once EMG is identified, treat any other still-pending usbmodem port as TENS.
        guard !useOpenEMSstim else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.promotePendingPortsToTens()
        }
    }

    private func promotePendingPortsToTens() {
        guard !useOpenEMSstim else { return }
        let stillPending = pendingBuffers.keys
        guard !stillPending.isEmpty else { return }
        let knownPorts = ORSSerialPortManager.shared().availablePorts
        for path in stillPending {
            guard let port = knownPorts.first(where: { $0.path == path }) else { continue }
            portRoles[path] = .tens
            pendingBuffers.removeValue(forKey: path)
            DispatchQueue.main.async {
                self.tensPort = port
                self.isTensConnected = true
                self.logs.append(LogEntry(text: "TENS CONNECTED (by elimination): \(port.path)"))
            }
        }
    }

    /// Returns the bytes that follow the line containing `marker`, so the EMG line parser starts cleanly.
    private func dropEverythingThrough(_ marker: String, in text: String) -> Data {
        guard let range = text.range(of: marker) else { return Data() }
        let afterMarker = text[range.upperBound...]
        let afterLine = afterMarker.drop(while: { $0 != "\n" }).dropFirst()
        return String(afterLine).data(using: .utf8) ?? Data()
    }

    private func processEMGData(_ data: Data) {
        emgLineBuffer.append(data)
        guard let totalString = String(data: emgLineBuffer, encoding: .utf8) else { return }
        var lines = totalString.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }

        let fragment = lines.removeLast()
        emgLineBuffer = fragment.data(using: .utf8) ?? Data()
        for line in lines {
            let clean = line.replacingOccurrences(of: "VALUE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let rawValue = Double(clean) {
                processNewValue(rawValue)
                if !isPaused && Date().timeIntervalSince(lastUIUpdate) > 0.01 {
                    let absoluteMV = rawValue * rawToMillivolts
                    let logText = String(format: "%.4f mV", absoluteMV)
                    DispatchQueue.main.async {
                        self.logs.append(LogEntry(text: logText))
                        if self.logs.count > 500 { self.logs.removeFirst() }
                        self.lastUIUpdate = Date()
                    }
                }
            }
        }
    }

    func serialPortWasOpened(_ port: ORSSerialPort) {
        // Connection state is committed once the port self-identifies via SYSTEM_START_*.
        Logger.serial.info("Port opened, awaiting identification: \(port.path)")
    }

    func serialPortWasRemovedFromSystem(_ port: ORSSerialPort) {
        let role = portRoles.removeValue(forKey: port.path)
        pendingBuffers.removeValue(forKey: port.path)

        DispatchQueue.main.async {
            switch role {
            case .emg:
                self.isConnected = false
                self.serialPort = nil
                self.logs.append(LogEntry(text: "EMG DISCONNECTED: \(port.path)"))
            case .tens:
                self.isTensConnected = false
                self.tensPort = nil
                self.emsReady = false
                self.logs.append(LogEntry(text: "TENS DISCONNECTED: \(port.path)"))
            case .none:
                self.logs.append(LogEntry(text: "PORT REMOVED (unidentified): \(port.path)"))
            }
        }
    }

    func serialPort(_ port: ORSSerialPort, didEncounterError error: Error) {
        let role = portRoles[port.path]
        DispatchQueue.main.async {
            switch role {
            case .emg: self.isConnected = false
            case .tens: self.isTensConnected = false
            case .none: break
            }
        }
    }
}

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.tandem.neuro"
    static let serial = Logger(subsystem: subsystem, category: "SerialStream")
}
