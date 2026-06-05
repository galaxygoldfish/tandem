#!/usr/bin/env python3
"""
test_openEMSstim.py
Standalone tester for the openEMSstim output path — mirrors SerialManager.swift
when useOpenEMSstim = true (command format, ramp, interval, hold, abort).

Usage:
  # Print commands only (safest — no hardware):
  python3 test_openEMSstim.py --dry-run --simulate

  # Simulated flex curve on real board (electrodes OFF for first run):
  python3 test_openEMSstim.py --ems /dev/tty.wchusbserialXXXX --simulate --ceiling 10 --confirm

  # Full EMG → EMS (same mapping as the Swift app):
  python3 test_openEMSstim.py --emg /dev/tty.usbmodemXXXX --ems /dev/tty.wchusbserialXXXX --confirm

  ls /dev/tty.*   # find ports
"""

import argparse
import collections
import sys
import time
import tty
import termios

import serial

# --- constants aligned with SerialManager.swift (useOpenEMSstim path) ---
EMS_BAUD = 19200
EMG_BAUD = 115200
EMS_BOOT_WAIT_S = 10
SENSORY_THRESHOLD = 0.15
RAMP_STEP_UP = 1
RAMP_STEP_DOWN = 2
INTENSITY_SMOOTHING = 0.12  # EMA on activation 0–1 (lower = smoother)
OUTPUT_CURVE_EXP = 1.4      # >1 = slower approach to ceiling, like easing a dial
PULSE_DURATION_MS = 150
SEND_INTERVAL_S = 0.1
HOLD_TIME_S = 1.0
EMS_RELEASE_S = 0.55        # fade to zero after flex (not a flat hold at peak)
TO_MILLIVOLTS = 0.00815
ENVELOPE_WINDOW = 20
BASELINE_ALPHA = 0.0001
BASELINE_ALPHA_FAST = 0.05
BASELINE_WARMUP_SAMPLES = 500


def map_to_tens_level(normalized: float) -> float:
    """Map activation to output level with threshold + soft curve (gentle ramp to max)."""
    if normalized < SENSORY_THRESHOLD:
        return 0.0
    safe = max(0.0, min(1.0, normalized))
    # Re-scale [threshold, 1] → [0, 1], then curve so max isn't reached suddenly.
    span = 1.0 - SENSORY_THRESHOLD
    t = (safe - SENSORY_THRESHOLD) / span
    return t ** OUTPUT_CURVE_EXP


def _smoothstep(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


class EMSOutput:
    """Maps smoothed activation → ramped EMS intensity commands."""

    def __init__(self, ceiling: int, ramp_step_up: int = RAMP_STEP_UP,
                 ramp_step_down: int = RAMP_STEP_DOWN, smoothing: float = INTENSITY_SMOOTHING):
        self.ceiling = min(ceiling, 100)
        self.ramp_step_up = max(1, ramp_step_up)
        self.ramp_step_down = max(1, ramp_step_down)
        self.smoothing = max(0.01, min(1.0, smoothing))
        self.last_intensity = 0
        self.smoothed_level = 0.0

    def command_for_level(self, level: float) -> str | None:
        # Follow releases faster than rises (dial back down quicker than up).
        alpha = self.smoothing * 2.8 if level < self.smoothed_level else self.smoothing
        alpha = min(1.0, alpha)
        self.smoothed_level += (level - self.smoothed_level) * alpha

        if self.smoothed_level < 0.001 and self.last_intensity == 0:
            return None

        curved = map_to_tens_level(self.smoothed_level)
        raw = int(curved * self.ceiling + 0.5)
        target = max(0, min(raw, self.ceiling))
        if target > self.last_intensity:
            ramped = min(target, self.last_intensity + self.ramp_step_up)
        else:
            ramped = max(target, self.last_intensity - self.ramp_step_down)
        self.last_intensity = ramped
        # Always send explicit I0 while ramping down so the channel fully closes.
        return f"C0I{ramped}T{PULSE_DURATION_MS}G"

    def zero_command(self) -> str:
        self.last_intensity = 0
        self.smoothed_level = 0.0
        return f"C0I0T{PULSE_DURATION_MS}G"

    def abort(self, port: serial.Serial | None, dry_run: bool) -> None:
        zero = self.zero_command()
        print(f"ABORT → {zero} (×3)")
        if port and not dry_run:
            for _ in range(3):
                port.write(zero.encode("utf-8"))


def send_value_with_hold(avg: float, last_active_time: float,
                         last_active_value: float, now: float,
                         use_hold: bool = True) -> tuple[float, float, float, float]:
    """Motor hold at peak; EMS eases out over EMS_RELEASE_S."""
    if avg >= SENSORY_THRESHOLD:
        last_active_time = now
        last_active_value = avg
        return avg, last_active_time, last_active_value, avg
    if not use_hold:
        elapsed = now - last_active_time
        if elapsed >= EMS_RELEASE_S or last_active_value <= 0:
            return 0.0, last_active_time, last_active_value, 0.0
        t = elapsed / EMS_RELEASE_S
        activation = last_active_value * (1.0 - t) ** 2
        return activation, last_active_time, last_active_value, activation
    in_hold = (now - last_active_time) < HOLD_TIME_S
    send_value = last_active_value if in_hold else 0.0
    return send_value, last_active_time, last_active_value, send_value


def simulated_activation(elapsed_s: float, cycle_s: float = 8.0) -> float:
    """Bell-curve flex: smooth up and down, brief peak — no flat hold at max."""
    phase = elapsed_s % cycle_s
    rest = cycle_s * 0.25       # 2s quiet
    flex_end = cycle_s * 0.75   # 4s flex window, then 2s quiet
    if phase < rest or phase >= flex_end:
        return 0.0
    t = (phase - rest) / (flex_end - rest)
    # Peaks at t=0.5 then falls; *4 scales bump max to 1.0
    bump = _smoothstep(t) * (1.0 - _smoothstep(t)) * 4.0
    return bump * 0.85


class EMGProcessor:
    """Minimal EMG pipeline from live_pipeline.py for --emg mode."""

    def __init__(self):
        self.dynamic_baseline = None
        self.warmup_count = 0
        self.envelope_buffer = collections.deque(maxlen=ENVELOPE_WINDOW)
        self.baseline_ref = None
        self.mvc_ref = None
        self.cal_samples = []
        self.mode = "live"

    def start_baseline(self):
        self.cal_samples = []
        self.mode = "baseline"
        print("\n[CAL] Baseline — relax 3–5 s, press b again")

    def stop_baseline(self):
        if self.cal_samples:
            self.baseline_ref = sum(self.cal_samples) / len(self.cal_samples)
            print(f"[CAL] Baseline: {self.baseline_ref:.5f} mV")
        self.mode = "live"

    def start_mvc(self):
        self.cal_samples = []
        self.mode = "mvc"
        print("\n[CAL] MVC — flex hard 2–3 s, press m again")

    def stop_mvc(self):
        if self.cal_samples:
            s = sorted(self.cal_samples)
            self.mvc_ref = s[int(0.95 * len(s))]
            print(f"[CAL] MVC: {self.mvc_ref:.5f} mV")
        self.mode = "live"

    def process(self, raw_adc: float) -> tuple[float, float]:
        if self.dynamic_baseline is None:
            self.dynamic_baseline = raw_adc
        self.warmup_count += 1
        alpha = BASELINE_ALPHA_FAST if self.warmup_count < BASELINE_WARMUP_SAMPLES else BASELINE_ALPHA
        self.dynamic_baseline = (raw_adc * alpha) + (self.dynamic_baseline * (1 - alpha))
        abs_mv = abs((raw_adc - self.dynamic_baseline) * TO_MILLIVOLTS)
        self.envelope_buffer.append(abs_mv)
        envelope = sum(self.envelope_buffer) / len(self.envelope_buffer)
        if self.mode in ("baseline", "mvc"):
            self.cal_samples.append(envelope)
        return envelope, self._normalize(envelope)

    def _normalize(self, envelope: float) -> float:
        if self.baseline_ref is None or self.mvc_ref is None or self.mvc_ref <= self.baseline_ref:
            return 0.0
        return max(0.0, min(1.0, (envelope - self.baseline_ref) / (self.mvc_ref - self.baseline_ref)))

    def is_calibrated(self) -> bool:
        return self.baseline_ref is not None and self.mvc_ref is not None


def ramp_to_zero(ems: EMSOutput, port: serial.Serial | None, dry_run: bool) -> None:
    """Step intensity down to 0 before abort (dial back to off)."""
    while ems.last_intensity > 0:
        cmd = f"C0I{max(0, ems.last_intensity - ems.ramp_step)}T{PULSE_DURATION_MS}G"
        ems.last_intensity = max(0, ems.last_intensity - ems.ramp_step)
        print(f"RAMP DOWN → {cmd}")
        if port and not dry_run:
            port.write(cmd.encode("utf-8"))
        time.sleep(SEND_INTERVAL_S)
    zero = ems.zero_command()
    print(f"OFF → {zero}")
    if port and not dry_run:
        for _ in range(3):
            port.write(zero.encode("utf-8"))


def run_output_loop(
    get_normalized,
    ems: EMSOutput,
    port: serial.Serial | None,
    dry_run: bool,
    duration_s: float | None,
    use_hold: bool = False,
) -> None:
    last_sent = 0.0
    last_active_time = 0.0
    last_active_value = 0.0
    window_samples: list[float] = []
    start = time.time()

    print(f"\nOutput loop — send every {SEND_INTERVAL_S}s, ceiling={ems.ceiling}, dry_run={dry_run}")
    print("Press q to abort.\n")

    try:
        while True:
            if duration_s is not None and (time.time() - start) >= duration_s:
                break

            normalized = get_normalized()
            window_samples.append(normalized)
            now = time.time()
            if now - last_sent < SEND_INTERVAL_S:
                time.sleep(0.001)
                continue
            last_sent = now

            avg = sum(window_samples) / len(window_samples) if window_samples else 0.0
            window_samples.clear()

            send_value, last_active_time, last_active_value, activation = send_value_with_hold(
                avg, last_active_time, last_active_value, now, use_hold=use_hold
            )
            cmd = ems.command_for_level(activation)
            if cmd:
                label = f"activation={avg:.0%}  I={ems.last_intensity}  → {cmd}"
            else:
                label = f"activation={avg:.0%}  → off"
            print(label)
            if cmd and port and not dry_run:
                port.write(cmd.encode("utf-8"))

            time.sleep(0.001)
    except KeyboardInterrupt:
        print("\nInterrupted.")
    finally:
        ramp_to_zero(ems, port, dry_run)


def run_simulate(args, port):
    ems = EMSOutput(args.ceiling, ramp_step_up=args.ramp_step, smoothing=args.smoothing)
    start = time.time()

    def get_norm():
        return simulated_activation(time.time() - start, args.cycle)

    run_output_loop(get_norm, ems, port, args.dry_run, args.duration, use_hold=False)


def run_emg(args, port):
    print(f"Connecting EMG on {args.emg}...")
    emg_port = serial.Serial(args.emg, EMG_BAUD, timeout=1)
    time.sleep(2)
    processor = EMGProcessor()
    ems = EMSOutput(args.ceiling, ramp_step_up=args.ramp_step, smoothing=args.smoothing)
    data_buffer = ""

    def input_listener():
        while True:
            fd = sys.stdin.fileno()
            old = termios.tcgetattr(fd)
            try:
                tty.setcbreak(fd)
                key = sys.stdin.read(1)
            finally:
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
            if key == "b":
                processor.stop_baseline() if processor.mode == "baseline" else processor.start_baseline()
            elif key == "m":
                processor.stop_mvc() if processor.mode == "mvc" else processor.start_mvc()
            elif key in ("q", "\x03"):
                return

    import threading
    threading.Thread(target=input_listener, daemon=True).start()
    print("Calibrate: b = baseline, m = MVC, q = quit\n")

    last_sent = 0.0
    last_active_time = 0.0
    last_active_value = 0.0
    window_samples: list[float] = []

    try:
        while True:
            chunk = emg_port.read(emg_port.in_waiting or 1)
            if not chunk:
                continue
            data_buffer += chunk.decode("utf-8", errors="ignore")
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
                    print(f"  EMG: {envelope:.4f} mV  (calibrate: b then m)", end="\r")
                    continue
                window_samples.append(normalized)
                now = time.time()
                if now - last_sent < SEND_INTERVAL_S:
                    continue
                last_sent = now
                avg = sum(window_samples) / len(window_samples)
                window_samples.clear()
                _, last_active_time, last_active_value, activation = send_value_with_hold(
                    avg, last_active_time, last_active_value, now, use_hold=False
                )
                cmd = ems.command_for_level(activation)
                if cmd:
                    print(f"  EMG: {envelope:.4f} mV  act={avg:.0%}  → {cmd}          ")
                    if port and not args.dry_run:
                        port.write(cmd.encode("utf-8"))
                else:
                    print(f"  EMG: {envelope:.4f} mV  act={avg:.0%}                  ", end="\r")
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        ramp_to_zero(ems, port, args.dry_run)
        emg_port.close()


def main():
    parser = argparse.ArgumentParser(
        description="Test openEMSstim using the same output mapping as SerialManager.swift"
    )
    parser.add_argument("--ems", help="openEMSstim serial port (wchusbserial*)")
    parser.add_argument("--emg", help="Spikerbox EMG port (usbmodem*) — enables live EMG mode")
    parser.add_argument("--simulate", action="store_true",
                        help="Fake flex curve (default when --emg is omitted)")
    parser.add_argument("--dry-run", action="store_true", help="Print commands, do not send")
    parser.add_argument("--confirm", action="store_true",
                        help="Required to send to real hardware (safety)")
    parser.add_argument("--ceiling", type=int, default=30,
                        help="Max intensity 0–100 (Swift: min(maxServoDegrees, 100))")
    parser.add_argument("--duration", type=float, default=8.0,
                        help="Simulate mode run length in seconds (default 8)")
    parser.add_argument("--cycle", type=float, default=8.0,
                        help="Simulated flex cycle length in seconds (default 8)")
    parser.add_argument("--ramp-step", type=int, default=RAMP_STEP_UP,
                        help="Max intensity increase per tick (default 1; down uses 2)")
    parser.add_argument("--smoothing", type=float, default=INTENSITY_SMOOTHING,
                        help="Activation EMA 0–1 (lower = smoother, default 0.12)")
    args = parser.parse_args()

    if args.ceiling < 0 or args.ceiling > 100:
        print("Error: --ceiling must be 0–100")
        sys.exit(1)
    if args.ramp_step < 1:
        print("Error: --ramp-step must be >= 1")
        sys.exit(1)

    use_hardware = bool(args.ems) and not args.dry_run
    if use_hardware and not args.confirm:
        print("Error: sending to hardware requires --confirm (and --ems PORT).")
        print("Use --dry-run first to inspect commands.")
        sys.exit(1)

    port = None
    if args.ems and not args.dry_run:
        print(f"Connecting openEMSstim on {args.ems} @ {EMS_BAUD}...")
        port = serial.Serial(args.ems, EMS_BAUD, timeout=1)
        print(f"Waiting {EMS_BOOT_WAIT_S}s for board init...")
        time.sleep(EMS_BOOT_WAIT_S)
        print("EMS ready.\n")
    elif args.dry_run:
        print("DRY RUN — commands printed only.\n")

    if args.emg:
        run_emg(args, port)
    else:
        print("SIMULATE mode — fake flex curve (rest → ramp → hold → release)")
        run_simulate(args, port)
        if port:
            port.close()


if __name__ == "__main__":
    main()
