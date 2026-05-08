#!/usr/bin/env python3
"""
live_pipeline.py
Reads raw EMG from Spikerbox over serial, runs signal processing,
maps to openEMSstim commands, and sends them to the board.

Usage:
    python3 live_pipeline.py --emg /dev/tty.usbmodemXXXX --ems /dev/tty.wchusbserialXXXX

Find your ports: ls /dev/tty.*
"""

import sys
import time
import argparse
import collections
import configparser
import threading
sys.path.insert(0, "../openEMSstim/apps/python")

import serial
from pyEMS.EMSCommand import ems_command

CALIBRATION_FILE  = "calibration.ems"
EMG_BAUD          = 115200
EMS_BAUD          = 19200
TO_MILLIVOLTS     = 0.00543
ENVELOPE_WINDOW   = 20
BASELINE_ALPHA    = 0.005
SENSORY_THRESHOLD = 0.15
RAMP_STEP         = 5
DEFAULT_DURATION  = 500
TENS_INTERVAL     = 0.1

def load_calibration(filepath):
    config = configparser.ConfigParser()
    config.read(filepath)
    return {
        "channel1_ceiling": int(config["intensity"]["channel1"]),
        "channel2_ceiling": int(config["intensity"]["channel2"]),
    }

class EMGProcessor:
    def __init__(self):
        self.dynamic_baseline = 300.0
        self.envelope_buffer  = collections.deque(maxlen=ENVELOPE_WINDOW)
        self.baseline_ref     = None
        self.mvc_ref          = None
        self.cal_samples      = []
        self.mode             = "live"

    def start_baseline(self):
        self.cal_samples = []
        self.mode = "baseline"
        print("\n[CAL] Baseline started — relax arm completely for 3-5 seconds, then press Enter")

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
        print("\n[CAL] MVC started — flex hard for 2-3 seconds, then press Enter")

    def stop_mvc(self):
        if self.cal_samples:
            sorted_s = sorted(self.cal_samples)
            idx = int(0.95 * len(sorted_s))
            self.mvc_ref = sorted_s[min(idx, len(sorted_s)-1)]
            print(f"[CAL] MVC set: {self.mvc_ref:.5f} mV ({len(self.cal_samples)} samples)")
        else:
            print("[CAL] No samples collected")
        self.mode = "live"

    def process(self, raw_adc):
        self.dynamic_baseline = (raw_adc * BASELINE_ALPHA) + (self.dynamic_baseline * (1 - BASELINE_ALPHA))
        centered = raw_adc - self.dynamic_baseline
        abs_mv = abs(centered * TO_MILLIVOLTS)
        if self.mode in ("baseline", "mvc"):
            self.cal_samples.append(abs_mv)
        self.envelope_buffer.append(abs_mv)
        envelope = sum(self.envelope_buffer) / len(self.envelope_buffer)
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

_last_intensity = {1: 0, 2: 0}

def ramped_intensity(channel, target):
    last = _last_intensity[channel]
    clamped = min(target, last + RAMP_STEP) if target > last else max(target, last - RAMP_STEP)
    _last_intensity[channel] = clamped
    return clamped

def activation_to_command(activation_norm, channel, cal, duration=DEFAULT_DURATION):
    if activation_norm < SENSORY_THRESHOLD:
        _last_intensity[channel] = 0
        return None
    ceiling = cal[f"channel{channel}_ceiling"]
    raw = int(activation_norm * ceiling)
    safe = ramped_intensity(channel, max(0, min(raw, ceiling)))
    return ems_command(channel, safe, duration)

def main():
    parser = argparse.ArgumentParser(description="Tandem live EMG-to-TENS pipeline")
    parser.add_argument("--emg", required=True, help="Serial port for Spikerbox EMG Arduino")
    parser.add_argument("--ems", required=True, help="Serial port for openEMSstim board")
    parser.add_argument("--channel", type=int, default=1, choices=[1,2], help="EMS channel (default: 1)")
    args = parser.parse_args()

    cal = load_calibration(CALIBRATION_FILE)
    print(f"Calibration loaded: ch1 ceiling={cal['channel1_ceiling']}, ch2 ceiling={cal['channel2_ceiling']}")

    print(f"\nConnecting to Spikerbox on {args.emg}...")
    emg_port = serial.Serial(args.emg, EMG_BAUD, timeout=1)
    time.sleep(2)
    print("Spikerbox connected.")

    print(f"Connecting to openEMSstim on {args.ems}...")
    ems_port = serial.Serial(args.ems, EMS_BAUD, timeout=1)
    print("Waiting 10s for openEMSstim board to initialize...")
    time.sleep(10)
    print("openEMSstim ready.")

    processor = EMGProcessor()
    data_buffer = ""
    last_tens_time = 0.0

    print("\n" + "="*55)
    print("TANDEM LIVE PIPELINE")
    print("="*55)
    print("  b  — start/stop baseline calibration")
    print("  m  — start/stop MVC calibration")
    print("  q  — quit")
    print("="*55)
    print("\nStart with baseline (press b), then MVC (press m)\n")

    def input_listener():
        while True:
            key = input()
            if key.strip() == "b":
                if processor.mode == "baseline":
                    processor.stop_baseline()
                else:
                    processor.start_baseline()
            elif key.strip() == "m":
                if processor.mode == "mvc":
                    processor.stop_mvc()
                else:
                    processor.start_mvc()
            elif key.strip() == "q":
                print("\nQuitting...")
                emg_port.close()
                ems_port.close()
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
                    continue
                now = time.time()
                if now - last_tens_time < TENS_INTERVAL:
                    continue
                last_tens_time = now
                cmd = activation_to_command(normalized, args.channel, cal)
                if cmd:
                    ems_port.write(cmd.encode("utf-8"))
                    print(f"  norm={normalized:.3f}  cmd={cmd}")
                else:
                    print(f"  norm={normalized:.3f}  NO STIM", end="\r")
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        emg_port.close()
        ems_port.close()

if __name__ == "__main__":
    main()
