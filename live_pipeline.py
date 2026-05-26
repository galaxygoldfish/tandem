#!/usr/bin/env python3
"""
live_pipeline.py
Reads raw EMG from Spikerbox over serial, runs signal processing,
maps to openEMSstim commands, and sends them to the board.

Usage:
    python3 live_pipeline.py --emg /dev/tty.usbmodemXXXX --ems /dev/tty.wchusbserialXXXX

Find your ports: ls /dev/tty.*
"""

### COMMAND TO RUN IN TERMINAL: python3 live_pipeline.py --emg /dev/tty.usbmodem1101 --dry-run
## (TO JUST SEE RAW mV VALUE: python3 live_pipeline.py --emg /dev/tty.usbmodem1101 --dry-run --raw)

# Standard EMG pipeline is:
# raw ADC → dynamic baseline → rectify → mV → envelope → calibrate → normalize → stim

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
try:
    from pyEMS.EMSCommand import ems_command
except ModuleNotFoundError:
    def ems_command(channel, intensity, duration):
        return f"CH{channel} intensity={intensity} duration={duration}ms"

CALIBRATION_FILE  = "calibration.ems"
EMG_BAUD          = 115200
EMS_BAUD          = 19200
TO_MILLIVOLTS     = 0.00815  # 5000mV / 1023 / 600x gain (SpikerShield)
ENVELOPE_WINDOW   = 20
BASELINE_ALPHA       = 0.0001
BASELINE_ALPHA_FAST  = 0.05    # used for first BASELINE_WARMUP_SAMPLES to snap to true resting level asap
BASELINE_WARMUP_SAMPLES = 500
# no command to TENS sent if activation drops below 0.05 (5% of calibrated range)
# TENS command is sent only once envelope rises at least 15% of the way from resting state to MVC
SENSORY_THRESHOLD = 0.15
RAMP_STEP         = 5
DEFAULT_DURATION  = 150 # stim stays continous while muscle is active but stops within 150 ms of dropping below threshold
TENS_INTERVAL     = 0.1 # commands to TENS go out every 100 ms


def load_calibration(filepath):
    config = configparser.ConfigParser()
    config.read(filepath)
    return {
        "channel1_ceiling": int(config["intensity"]["channel1"]),
        "channel2_ceiling": int(config["intensity"]["channel2"]),
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
            print(f"[CAL] No samples collected — serial data may not be flowing")
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
                print(f"[CAL] WARNING: MVC ({self.mvc_ref:.5f}) <= baseline ({self.baseline_ref:.5f})")
                print("[CAL] Signal may not have settled. Wait ~5s, then redo: press b (relax), b, m (flex hard), m")
        else:
            print("[CAL] No samples collected")
        self.mode = "live"

    def process(self, raw_adc):
        if self.dynamic_baseline is None:
            self.dynamic_baseline = raw_adc
        self.warmup_count += 1
        alpha = BASELINE_ALPHA_FAST if self.warmup_count < BASELINE_WARMUP_SAMPLES else BASELINE_ALPHA
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
    parser.add_argument("--ems", required=False, help="Serial port for openEMSstim board")
    parser.add_argument("--channel", type=int, default=1, choices=[1,2], help="EMS channel (default: 1)")

    ## CHANGE WHEN WE ACTUALLY USE PHYSICAL EMS STIM. RN WE JUST ARE LOOKING AT COMMANDS
    ## WOULD BE SENT, WITHOUT USING THE ACTUAL EMS PORT
    parser.add_argument("--dry-run", action="store_true", help="Skip EMS board — print commands instead of sending")
    parser.add_argument("--raw", action="store_true", help="Print raw ADC→mV values with no baseline correction or envelope")
    args = parser.parse_args()

    cal = load_calibration(CALIBRATION_FILE)
    print(f"Calibration loaded: ch1 ceiling={cal['channel1_ceiling']}, ch2 ceiling={cal['channel2_ceiling']}")

    print(f"\nConnecting to Spikerbox on {args.emg}...")
    emg_port = serial.Serial(args.emg, EMG_BAUD, timeout=1)
    time.sleep(2)
    print("Spikerbox connected.")

    if args.dry_run:
        ems_port = None
        print("DRY RUN — EMS commands will be printed, not sent.")
    else:
        print(f"Connecting to openEMSstim on {args.ems}...")
        ems_port = serial.Serial(args.ems, EMS_BAUD, timeout=1)
        print("Waiting 10s for openEMSstim board to initialize...")
        time.sleep(10)
        print("openEMSstim ready.")

    processor = EMGProcessor()
    data_buffer = ""
    last_tens_time = 0.0
    session_log = []
    session_start = time.time()


    print("\n" + "="*55)
    print("TANDEM LIVE PIPELINE")
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
                if ems_port:
                    ems_port.close()
                if session_log:
                    fname = f"session_{time.strftime('%Y%m%d_%H%M%S')}.csv"
                    with open(fname, "w", newline="") as f:
                        writer = csv.writer(f)
                        writer.writerow(["time_s", "envelope_mV", "activation", "intensity"])
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
                if args.raw:
                    print(f"  RAW: {raw_adc * TO_MILLIVOLTS:.4f} mV", end="\r")
                    continue
                envelope, normalized = processor.process(raw_adc)
                if not processor.is_calibrated():
                    print(f"  EMG: {envelope:.4f} mV  (calibrate first)", end="\r")
                    continue
                now = time.time()
                if now - last_tens_time < TENS_INTERVAL:
                    continue
                last_tens_time = now
                cmd = activation_to_command(normalized, args.channel, cal)
                intensity = _last_intensity[args.channel]
                session_log.append([round(now - session_start, 3), round(envelope, 5), round(normalized, 4), intensity])
                if cmd:
                    if ems_port:
                        ems_port.write(cmd.encode("utf-8"))
                    print(f"  EMG: {envelope:.4f} mV  activation: {normalized:.0%}  → {cmd}")
                else:
                    print(f"  EMG: {envelope:.4f} mV  activation: {normalized:.0%}")
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        emg_port.close()
        if ems_port:
            ems_port.close()

if __name__ == "__main__":
    main()
