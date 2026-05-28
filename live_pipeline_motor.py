#!/usr/bin/env python3
"""
live_pipeline_motor.py
Backup plan: reads EMG from Spikerbox, maps activation to servo degrees,
sends to motor Arduino.

Usage (testing):
    python3 live_pipeline_motor.py --emg /dev/tty.usbmodemXXXX --motor /dev/tty.usbmodemYYYY

Find your ports: ls /dev/tty.*
Note: motor Arduino baud rate is 9600 for testing, 115200 for final hardware.
"""

import sys
import time
import argparse
import collections
import configparser
import threading
import tty
import termios
import csv
sys.path.insert(0, "../openEMSstim/apps/python")

import serial

CALIBRATION_FILE     = "calibration.ems"
EMG_BAUD             = 115200
MOTOR_BAUD           = 115200    # change to 115200 for real hardware
TO_MILLIVOLTS        = 0.00815
ENVELOPE_WINDOW      = 20
BASELINE_ALPHA       = 0.0001
BASELINE_ALPHA_FAST  = 0.05
BASELINE_WARMUP      = 500
SENSORY_THRESHOLD    = 0.15
MAX_DEGREES          = 100
SEND_INTERVAL        = 0.5   # send averaged command every 500ms
AVERAGE_WINDOW       = 0.5   # average normalized values over this window before sending

def load_calibration(filepath):
    config = configparser.ConfigParser()
    config.read(filepath)
    return {
        "channel1_ceiling": int(config["intensity"]["channel1"]),
    }

class EMGProcessor:
    def __init__(self):
        self.dynamic_baseline = None
        self.warmup_count     = 0
        self.envelope_buffer  = collections.deque(maxlen=ENVELOPE_WINDOW)
        self.baseline_ref     = None
        self.mvc_ref          = None
        self.cal_samples      = []
        self.mode             = "live"

    def start_baseline(self):
        self.cal_samples = []
        self.mode = "baseline"
        print("\n[CAL] Baseline started — relax arm completely for 3-5 seconds, then press b again")

    def stop_baseline(self):
        if self.cal_samples:
            self.baseline_ref = sum(self.cal_samples) / len(self.cal_samples)
            print(f"[CAL] Baseline set: {self.baseline_ref:.5f} mV ({len(self.cal_samples)} samples)")
        else:
            print("[CAL] No samples collected")
        self.mode = "live"

    def start_mvc(self):
        self.cal_samples = []
        self.mode = "mvc"
        print("\n[CAL] MVC started — flex hard for 2-3 seconds, then press m again")

    def stop_mvc(self):
        if self.cal_samples:
            sorted_s = sorted(self.cal_samples)
            idx = int(0.95 * len(sorted_s))
            self.mvc_ref = sorted_s[min(idx, len(sorted_s)-1)]
            print(f"[CAL] MVC set: {self.mvc_ref:.5f} mV ({len(self.cal_samples)} samples)")
            if self.baseline_ref is not None and self.mvc_ref <= self.baseline_ref:
                print("[CAL] WARNING: MVC <= baseline, redo calibration")
        else:
            print("[CAL] No samples collected")
        self.mode = "live"

    def process(self, raw_adc):
        if self.dynamic_baseline is None:
            self.dynamic_baseline = raw_adc
        self.warmup_count += 1
        alpha = BASELINE_ALPHA_FAST if self.warmup_count < BASELINE_WARMUP else BASELINE_ALPHA
        self.dynamic_baseline = (raw_adc * alpha) + (self.dynamic_baseline * (1 - alpha))
        centered = raw_adc - self.dynamic_baseline
        abs_mv = abs(centered * TO_MILLIVOLTS)
        self.envelope_buffer.append(abs_mv)
        envelope = sum(self.envelope_buffer) / len(self.envelope_buffer)
        if self.mode in ("baseline", "mvc"):
            self.cal_samples.append(envelope)
        normalized = self._normalize(envelope)
        return envelope, normalized

    def _normalize(self, envelope):
        if self.baseline_ref is None or self.mvc_ref is None:
            return 0.0
        if self.mvc_ref <= self.baseline_ref:
            return 0.0
        raw = (envelope - self.baseline_ref) / (self.mvc_ref - self.baseline_ref)
        return max(0.0, min(1.0, raw))

    def is_calibrated(self):
        return self.baseline_ref is not None and self.mvc_ref is not None

def activation_to_motor_command(activation_norm, max_degrees=MAX_DEGREES):
    if activation_norm < SENSORY_THRESHOLD:
        return "0\n"
    degrees = int(activation_norm * max_degrees)
    degrees = max(0, min(degrees, max_degrees))
    return f"{degrees}\n"

def main():
    parser = argparse.ArgumentParser(description="Tandem motor backup pipeline")
    parser.add_argument("--emg", required=True, help="Serial port for Spikerbox")
    parser.add_argument("--motor", required=False, help="Serial port for motor Arduino")
    parser.add_argument("--dry-run", action="store_true", help="Print commands instead of sending")
    parser.add_argument("--max-degrees", type=int, default=MAX_DEGREES, help="Max servo degrees (default 100)")
    args = parser.parse_args()

    print(f"Connecting to Spikerbox on {args.emg}...")
    emg_port = serial.Serial(args.emg, EMG_BAUD, timeout=1)
    time.sleep(2)
    print("Spikerbox connected.")

    if args.dry_run:
        motor_port = None
        print("DRY RUN — motor commands will be printed, not sent.")
    else:
        print(f"Connecting to motor Arduino on {args.motor} at {MOTOR_BAUD} baud...")
        motor_port = serial.Serial(args.motor, MOTOR_BAUD, timeout=1)
        time.sleep(2)
        print("Motor Arduino connected.")

    processor = EMGProcessor()
    data_buffer = ""
    last_send_time = 0.0
    window_samples = []
    session_log = []
    session_start = time.time()

    print("\n" + "="*55)
    print("TANDEM MOTOR BACKUP PIPELINE")
    print("="*55)
    print("  b  — start/stop baseline calibration")
    print("  m  — start/stop MVC calibration")
    print("  q  — quit")
    print("="*55)
    print("\nStart with baseline (press b), then MVC (press m)\n")

    def getch():
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setcbreak(fd)
            return sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)

    def input_listener():
        while True:
            key = getch()
            if key == "b":
                if processor.mode == "baseline":
                    processor.stop_baseline()
                else:
                    processor.start_baseline()
            elif key == "m":
                if processor.mode == "mvc":
                    processor.stop_mvc()
                else:
                    processor.start_mvc()
            elif key in ("q", "\x03"):
                print("\nQuitting...")
                emg_port.close()
                if motor_port:
                    motor_port.write(b"0\n")  # return servo to 0 on quit
                    motor_port.close()
                if session_log:
                    fname = f"motor_session_{time.strftime('%Y%m%d_%H%M%S')}.csv"
                    with open(fname, "w", newline="") as f:
                        writer = csv.writer(f)
                        writer.writerow(["time_s", "envelope_mV", "activation", "degrees"])
                        writer.writerows(session_log)
                    print(f"Session saved to {fname}")
                sys.exit(0)

    threading.Thread(target=input_listener, daemon=True).start()

    try:
        while True:
            raw_data = emg_port.read(emg_port.in_waiting or 1)
            if not raw_data:
                continue
            data_buffer += raw_data.decode("utf-8", errors="ignore")
            lines = data_buffer.split("\n")
            data_buffer = lines[-1]
            for line in lines[:-1]:
                clean = line.replace("VALUE:", "").strip()
                if not clean:
                    continue
                try:
                    raw_adc = float(clean)
                except ValueError:
                    continue
                envelope, normalized = processor.process(raw_adc)
                if not processor.is_calibrated():
                    print(f"  EMG: {envelope:.4f} mV  (calibrate first)", end="\r")
                    continue
                now = time.time()
                window_samples.append(normalized)
                if now - last_send_time < SEND_INTERVAL:
                    continue
                last_send_time = now
                avg_normalized = sum(window_samples) / len(window_samples)
                window_samples.clear()
                cmd = activation_to_motor_command(avg_normalized, args.max_degrees)
                degrees = int(cmd.strip())
                session_log.append([round(now - session_start, 3), round(envelope, 5), round(avg_normalized, 4), degrees])
                if motor_port:
                    motor_port.write(cmd.encode("utf-8"))
                print(f"  EMG: {envelope:.4f} mV  activation: {avg_normalized:.0%}  → {degrees} degrees")
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        emg_port.close()
        if motor_port:
            motor_port.write(b"0\n")
            motor_port.close()

if __name__ == "__main__":
    main()
