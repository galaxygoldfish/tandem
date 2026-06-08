#!/usr/bin/env python3
"""
ems_level_test.py
Feel-test for the openEMSstim board: holds a few FIXED intensity levels in turn,
each for a few seconds with an OFF pause in between, so you can tell by feel
whether changing `I` in "C0I{n}T150G" actually changes the sensation —
independent of the app, the slider, and the EMG pipeline.

Usage:
  # Electrodes ON, then:
  python3 ems_level_test.py --ems /dev/tty.wchusbserialXXXX --confirm

  # Custom levels / timing:
  python3 ems_level_test.py --ems /dev/tty.wchusbserialXXXX --confirm \
      --levels 5 50 100 --hold 4 --pause 3

  # Test the "commands overlap the pulse train" theory by resending slower
  # than the 150ms pulse duration (the app currently resends every 100ms):
  python3 ems_level_test.py --ems /dev/tty.wchusbserialXXXX --confirm --interval 0.2

  ls /dev/tty.*   # find your port
"""

import argparse
import time

import serial

EMS_BAUD = 19200
EMS_BOOT_WAIT_S = 10
PULSE_DURATION_MS = 150


def cmd_for(intensity: int) -> bytes:
    return f"C0I{intensity}T{PULSE_DURATION_MS}G".encode("utf-8")


def hold_level(port: serial.Serial, intensity: int, hold_s: float, interval_s: float) -> None:
    cmd = cmd_for(intensity)
    print(f"  → I={intensity}  holding {hold_s:.0f}s (resend every {interval_s:.2f}s) — feel it now")
    end = time.time() + hold_s
    while time.time() < end:
        port.write(cmd)
        time.sleep(interval_s)


def main():
    parser = argparse.ArgumentParser(description="Hold fixed EMS intensity levels so you can feel-test them in isolation")
    parser.add_argument("--ems", required=True, help="openEMSstim serial port (wchusbserial*)")
    parser.add_argument("--confirm", action="store_true", help="Required to actually send to hardware (safety)")
    parser.add_argument("--levels", type=int, nargs="+", default=[5, 50, 100],
                        help="Intensity values (0-100) to step through in order, default: 5 50 100")
    parser.add_argument("--hold", type=float, default=4.0, help="Seconds to hold each level (default 4)")
    parser.add_argument("--pause", type=float, default=3.0, help="Seconds OFF between levels (default 3)")
    parser.add_argument("--interval", type=float, default=0.1,
                        help="Seconds between resends while holding a level (default 0.1, matches the app)")
    args = parser.parse_args()

    for lvl in args.levels:
        if not (0 <= lvl <= 100):
            print(f"Error: level {lvl} out of range 0-100")
            return

    if not args.confirm:
        print("Refusing to send to hardware without --confirm (this delivers real stimulation).")
        print("Re-run with --confirm once electrodes are placed and you're ready.")
        return

    print(f"Connecting to openEMSstim on {args.ems} @ {EMS_BAUD}...")
    port = serial.Serial(args.ems, EMS_BAUD, timeout=1)
    print(f"Waiting {EMS_BOOT_WAIT_S}s for board init...")
    time.sleep(EMS_BOOT_WAIT_S)
    print("Ready.\n")
    print(f"Sequence: {args.levels}  (hold {args.hold}s, pause {args.pause}s, resend interval {args.interval}s)")
    print("Note what each level feels like, then compare. Ctrl+C to abort early.\n")

    off = cmd_for(0)

    try:
        for lvl in args.levels:
            hold_level(port, lvl, args.hold, args.interval)
            print(f"  → OFF, pausing {args.pause:.0f}s — write down what I={lvl} felt like\n")
            for _ in range(3):
                port.write(off)
            time.sleep(args.pause)
    except KeyboardInterrupt:
        print("\nInterrupted.")
    finally:
        for _ in range(3):
            port.write(off)
        port.close()
        print("Done — stimulation stopped.")


if __name__ == "__main__":
    main()
