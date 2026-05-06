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
    @Published var isPaused: Bool = false
    @Published var plotData: [Double] = Array(repeating: 0.0, count: 250)  // Waveform display buffer
    @Published var isRecording: Bool = false
    @Published var recordingTime: String = "00:00"
    @Published var isConsolePoppedOut: Bool = false
    
    // MARK: - EMG Processing & Calibration (NEW)
    /// Live normalized strength from EMG (0 = rest, 1 = max contraction).
    @Published var normalizedStrength: Double = 0.0
    /// Mapped TENS output level based on normalized strength [0, 1].
    @Published var tensOutput: Double = 0.0
    /// Whether to actively send TENS commands.
    @Published var isTensEnabled: Bool = false
    /// Captured baseline envelope (mV) — mean of quiet rest period.
    @Published var baselineMV: Double?
    /// Captured MVC envelope (mV) — 95th percentile of strong flex period.
    @Published var mvcMV: Double?
    /// Current calibration mode: none, baseline capture, or MVC capture.
    @Published var calibrationMode: CalibrationMode = .none
    
    // MARK: - Serial Port & Buffers
    var serialPort: ORSSerialPort?
    private var dataBuffer = Data()
    private var lastUIUpdate = Date()
    private var lastTensSent = Date(timeIntervalSince1970: 0)  // Throttle TENS commands
    
     // MARK: - Signal Processing Constants
    @Published var dynamicBaseline: Double = 300.0  // Slow drift correction baseline
    private var smoothedValue: Double = 0.0  // Exponentially smoothed display value
    private let signalSmoothing: Double = 0.15  // Waveform display smoothing
    private let baselineSmoothing: Double = 0.005  // Drift correction alpha
    private let gainMultiplier: Double = 500.0  // Visual scaling for plot
    
    // MARK: - Calibration & Envelope Buffers
    private var baselineSamples: [Double] = []  // Samples captured during baseline calibration
    private var mvcSamples: [Double] = []  // Samples captured during MVC calibration
    private var envelopeBuffer: [Double] = []  // Short buffer for envelope smoothing (~20 samples)

    /// Calibration mode enum: tracks whether we're capturing baseline or MVC.
    enum CalibrationMode {
        case none
        case baseline
        case mvc
    }
    
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var recordedData: [(timestamp: Int64, signal: Double, normalized: Double, tens: Double)] = []

    override init() {
        super.init()
        
        setupPort()
        
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(portsChanged(_:)), name: NSNotification.Name.ORSSerialPortsWereConnected, object: nil)
        nc.addObserver(self, selector: #selector(portsChanged(_:)), name: NSNotification.Name.ORSSerialPortsWereDisconnected, object: nil)
    }
    
    func recalibrate() {
        DispatchQueue.main.async {
            self.logs.append(LogEntry(text: "RECALIBRATED BASELINE"))
            self.plotData = Array(repeating: 0.0, count: 250)
            self.normalizedStrength = 0.0
            self.tensOutput = 0.0
            self.envelopeBuffer.removeAll()
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

    /// Map normalized strength [0, 1] to TENS output [0, 1] using a nonlinear curve.
    /// Exponent 1.8 means: gentle response at low levels, steep ramp at high levels.
    /// This prevents small arm movements from causing sudden large stimulation jumps.
    private func mapToTensLevel(_ normalized: Double) -> Double {
        let safeNormalized = max(0.0, min(1.0, normalized))
        let exponent = 1.8  // Tunable: >1 = nonlinear, 1 = linear, <1 = inverse
        return pow(safeNormalized, exponent)
    }

    /// Send TENS command to the device. Currently logs the command; integrate actual TENS hardware here.
    /// 
    /// TODO: Replace this with actual device communication:
    /// - Option 1: Second serial port (ORSSerialPort) to TENS hardware
    /// - Option 2: OpenEMSstim API call
    /// - Option 3: BLE/Bluetooth command
    /// 
    /// Example format (device-dependent):
    ///   - "AMPLITUDE:0.75\n" for normalized level
    ///   - "LEVEL:75" for 0-100 scale
    ///   - etc.
    private func sendTensCommand(_ level: Double) {
        let command = String(format: "TENS: %.3f", level)
        DispatchQueue.main.async {
            self.logs.append(LogEntry(text: "SEND → \(command)"))
        }
        // TODO: Implement actual TENS device communication here.
    }

    @objc func portsChanged(_ notification: Notification) {
        // Small delay allows the OS to fully register the port before we grab it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupPort()
        }
    }

    func setupPort() {
        let availablePorts = ORSSerialPortManager.shared().availablePorts
        let arduinoPort = availablePorts.first(where: {
            $0.path.contains("usbmodem") || $0.path.contains("usbserial")
        })
        
        // CASE 1: No Arduino found at all
        guard let port = arduinoPort else {
            DispatchQueue.main.async {
                self.isConnected = false
                self.serialPort = nil
            }
            return
        }
        
        // CASE 2: Arduino found. Check if we need to (re)open.
        let needsConnection = !isConnected || self.serialPort != port || !(self.serialPort?.isOpen ?? false)
        
        if needsConnection {
            self.serialPort?.delegate = nil
            self.serialPort?.close()
            
            self.serialPort = port
            self.serialPort?.baudRate = 115200
            self.serialPort?.delegate = self
            self.serialPort?.open()
            
            Logger.serial.info("Hardware found. Attempting connection to: \(port.path)")
        }
    }
    
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

    // Conversion factor for SpikerShield (5V ref, 10-bit, 900x gain)
    private let toMillivolts: Double = 0.00543

    private func processNewValue(_ value: Double) {
        dynamicBaseline = (value * baselineSmoothing) + (dynamicBaseline * (1 - baselineSmoothing))
        
        if isPaused { return }
        
        // Calculate the raw difference from baseline
        let centeredRaw = value - dynamicBaseline
        
        // Convert that difference to millivolts
        let centeredMV = centeredRaw * toMillivolts

        // Take absolute value (rectify) the centered EMG.
        let absMV = abs(centeredMV)
        
        // During calibration, collect samples for baseline or MVC computation.
        if calibrationMode == .baseline {
            baselineSamples.append(absMV)
        } else if calibrationMode == .mvc {
            mvcSamples.append(absMV)
        }

        // Maintain a short envelope buffer (~20 samples, 50 ms @ 1 kHz) for smoothing.
        envelopeBuffer.append(absMV)
        if envelopeBuffer.count > 20 { envelopeBuffer.removeFirst() }
        let envelope = envelopeBuffer.reduce(0, +) / Double(envelopeBuffer.count)

        // Scale for visual display (exponential smoothing for plot).
        let amplified = envelope * (gainMultiplier * 20)
        smoothedValue = (amplified * signalSmoothing) + (smoothedValue * (1 - signalSmoothing))
        
        // Compute normalized strength [0, 1] and map to TENS level.
        let normalized = computeNormalizedStrength(envelope)
        let tensLevel = mapToTensLevel(normalized)

        if isRecording, let start = recordingStartTime {
            let ms = Int64(Date().timeIntervalSince(start) * 1000)
            recordedData.append((timestamp: ms, signal: absMV, normalized: normalized, tens: tensLevel))
        }

        // Send TENS command at ~10 Hz (every 100 ms) if enabled.
        if isTensEnabled, Date().timeIntervalSince(lastTensSent) > 0.1 {
            lastTensSent = Date()
            sendTensCommand(tensLevel)
        }

        // Update UI with latest values.
        DispatchQueue.main.async {
            self.plotData.append(self.smoothedValue)
            if self.plotData.count > 250 { self.plotData.removeFirst() }
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
    
    private let rawToMillivolts: Double = (5.0 / 1023.0 / 900.0) * 1000.0 // approx 0.00543
    
    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        dataBuffer.append(data)
        guard let totalString = String(data: dataBuffer, encoding: .utf8) else { return }
        var lines = totalString.components(separatedBy: .newlines)
        
        if lines.count > 1 {
            let fragment = lines.removeLast()
            dataBuffer = fragment.data(using: .utf8) ?? Data()
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
    }

    func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.logs.append(LogEntry(text: "CONNECTED: \(serialPort.path)"))
        }
    }

    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.logs.append(LogEntry(text: "DISCONNECTED: \(serialPort.path)"))
            self.serialPort = nil
        }
    }
    
    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        DispatchQueue.main.async { self.isConnected = false }
    }
}

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.tandem.neuro"
    static let serial = Logger(subsystem: subsystem, category: "SerialStream")
}
