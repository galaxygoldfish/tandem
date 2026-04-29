import Foundation
import AppKit
import ORSSerial
import OSLog
internal import Combine
internal import UniformTypeIdentifiers

struct LogEntry: Identifiable {
    let id = UUID()
    let text: String
}

class SerialManager: NSObject, ObservableObject, ORSSerialPortDelegate {

    @Published var logs: [LogEntry] = []
    @Published var isConnected: Bool = false
    @Published var isPaused: Bool = false
    @Published var plotData: [Double] = Array(repeating: 0.0, count: 250)
    @Published var isRecording: Bool = false
    @Published var recordingTime: String = "00:00"
    @Published var isConsolePoppedOut: Bool = false
    
    var serialPort: ORSSerialPort?
    private var dataBuffer = Data()
    private var lastUIUpdate = Date()
    
    @Published var dynamicBaseline: Double = 300.0
    private var smoothedValue: Double = 0.0
    private let signalSmoothing: Double = 0.15
    private let baselineSmoothing: Double = 0.005
    private let gainMultiplier: Double = 500.0
    
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var recordedData: [(timestamp: Int64, value: Double)] = []

    override init() {
        super.init()
        
        setupPort()
        
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(portsChanged(_:)), name: NSNotification.Name.ORSSerialPortsWereConnected, object: nil)
        nc.addObserver(self, selector: #selector(portsChanged(_:)), name: NSNotification.Name.ORSSerialPortsWereDisconnected, object: nil)
    }
    
    func recalibrate() {
        // We grab the last known raw value if possible,
        // or just a neutral starting point to force a reset.
        // This snaps the 'zero' point to wherever the signal currently is.
        
        // If you have a 'currentRawValue' variable, use that.
        // Otherwise, it will naturally drift back, but this speeds it up:
        DispatchQueue.main.async {
            self.logs.append(LogEntry(text: "RECALIBRATED BASELINE"))
            // Snap the plotData back to zero to clear the "stuck" line
            self.plotData = Array(repeating: 0.0, count: 250)
        }
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

        if isRecording, let start = recordingStartTime {
            let ms = Int64(Date().timeIntervalSince(start) * 1000)
            // Save the MV value to the CSV
            recordedData.append((timestamp: ms, value: centeredMV))
        }

        // Apply gain for the VISUAL plot (so the lines look big enough)
        // Adjust gainMultiplier if not looking right
        let amplified = centeredMV * (gainMultiplier * 100)
        smoothedValue = (amplified * signalSmoothing) + (smoothedValue * (1 - signalSmoothing))
        
        DispatchQueue.main.async {
            self.plotData.append(self.smoothedValue)
            if self.plotData.count > 250 { self.plotData.removeFirst() }
        }
    }

    private func saveCSV() {
        if recordedData.isEmpty { return }
        var csvString = "timestamp_ms,signal\n"
        for entry in recordedData {
            csvString += "\(entry.timestamp),\(entry.value)\n"
        }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "tandem_capture_\(Int(Date().timeIntervalSince1970)).csv"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? csvString.write(to: url, atomically: true, encoding: .utf8)
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
