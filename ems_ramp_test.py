# #!/usr/bin/env python3
# """
# ems_ramp_test.py
# openEMSstim intensity check — one long pulse per level so I changes are obvious.

# The board only ATTENUATES your TENS unit. If every level feels the same:
#   - Turn the TENS unit dial DOWN so the board has headroom to modulate
#   - Confirm TENS → board INPUT, electrodes → board OUTPUT
#   - Try --channel 2 if pads are on channel 2

# Usage:
#   python3 ems_ramp_test.py --dry-run
#   python3 ems_ramp_test.py --ems /dev/tty.usbserial-210 --confirm
#   python3 ems_ramp_test.py --ems /dev/tty.usbserial-210 --confirm --hold 8 --channel 2
# """

# import argparse
# import time

# EMS_BAUD = 19200
# EMS_BOOT_WAIT_S = 10
# PULSE_DURATION_MS = 150       # used only with --repeat
# MAX_PULSE_MS = 5000          # firmware cap
# OFF_SETTLE_S = 0.2

# # Max contrast: low → high → low (0 = rest, no commands)
# RAMP_LEVELS = [0, 15, 80, 15, 0]


# def protocol_cmd(intensity: int, channel: int, duration_ms: int) -> str:
#     return f"C{channel}I{intensity}T{duration_ms}G"


# def cmd_for(intensity: int, channel: int, duration_ms: int, use_hex: bool) -> bytes:
#     inner = protocol_cmd(intensity, channel, duration_ms)
#     if use_hex:
#         hex_payload = inner.encode("ascii").hex().upper()
#         wire = f"WV,{len(hex_payload):04X},{hex_payload}.\n"
#     else:
#         wire = f"{inner}\n"
#     return wire.encode("ascii")


# def send_cmd(port, cmd: bytes) -> None:
#     port.write(cmd)
#     port.flush()


# def drain_serial(port, verbose: bool) -> None:
#     if not verbose:
#         return
#     while port.in_waiting:
#         line = port.readline().decode("utf-8", errors="replace").strip()
#         if line:
#             print(f"    [board] {line}")


# def pulse_ms_for_hold(hold_s: float) -> int:
#     return min(int(hold_s * 1000), MAX_PULSE_MS)


# def wait_with_countdown(hold_s: float, label: str) -> None:
#     end = time.time() + hold_s
#     last_tick = -1
#     while time.time() < end:
#         tick = int(end - time.time())
#         if tick != last_tick:
#             print(f"    … {tick + 1}s left {label}")
#             last_tick = tick
#         time.sleep(0.25)


# def hold_level(
#     port,
#     intensity: int,
#     channel: int,
#     hold_s: float,
#     dry_run: bool,
#     verbose: bool,
#     use_hex: bool,
#     repeat_mode: bool,
# ) -> None:
#     if intensity == 0:
#         print(f"\n>>> REST  {hold_s:.0f}s  (no commands — channel closes)")
#         if not dry_run:
#             wait_with_countdown(hold_s, "(off)")
#         return

#     pulse_ms = PULSE_DURATION_MS if repeat_mode else pulse_ms_for_hold(hold_s)
#     inner = protocol_cmd(intensity, channel, pulse_ms)
#     cmd = cmd_for(intensity, channel, pulse_ms, use_hex)

#     mode = f"resend every 0.1s, T={pulse_ms}ms" if repeat_mode else f"one pulse T={pulse_ms}ms"
#     print(f"\n>>> I={intensity:3d}  {hold_s:.0f}s  ({inner})")
#     print(f"    wire: {cmd.decode('ascii').rstrip()}")
#     print(f"    mode: {mode}")

#     if dry_run:
#         return

#     end = time.time() + hold_s
#     if repeat_mode:
#         while time.time() < end:
#             send_cmd(port, cmd)
#             time.sleep(0.1)
#     else:
#         # One command per level (matches official send_single_command.py).
#         # Re-send every ~4.5s if hold exceeds firmware T cap (5000 ms).
#         refresh_s = (MAX_PULSE_MS / 1000.0) - 0.5
#         while time.time() < end:
#             send_cmd(port, cmd)
#             remaining = end - time.time()
#             if remaining <= 0:
#                 break
#             sleep_s = min(refresh_s, remaining)
#             wait_with_countdown(sleep_s, f"at I={intensity}")

#     if verbose:
#         drain_serial(port, verbose)


# def main() -> None:
#     parser = argparse.ArgumentParser(
#         description="Step EMS intensity up/down to verify the board responds"
#     )
#     parser.add_argument("--ems", help="openEMSstim serial port")
#     parser.add_argument("--confirm", action="store_true",
#                         help="Required to send to real hardware")
#     parser.add_argument("--hold", type=float, default=6.0,
#                         help="Seconds per step (default 6; max pulse T capped at 5000 ms)")
#     parser.add_argument("--channel", type=int, default=1, choices=[1, 2],
#                         help="EMS channel 1→C0, 2→C1 (default 1)")
#     parser.add_argument("--repeat", action="store_true",
#                         help="Old mode: resend T150 every 100 ms (like live app)")
#     parser.add_argument("--verbose", action="store_true",
#                         help="Print board debug lines after each stim step")
#     parser.add_argument("--no-hex", action="store_true",
#                         help="Plain C0I…G (broken on stock firmware — use hex)")
#     parser.add_argument("--dry-run", action="store_true")
#     args = parser.parse_args()

#     channel_idx = args.channel - 1
#     use_hex = not args.no_hex
#     levels = RAMP_LEVELS
#     total_s = args.hold * len(levels)

#     if bool(args.ems) and not args.dry_run and not args.confirm:
#         print("Add --confirm to send real stimulation (or --dry-run to preview).")
#         return

#     print(f"Channel: {args.channel} (C{channel_idx})")
#     print(f"Wire: {'WV hex (required on stock firmware)' if use_hex else 'plain (likely broken)'}")
#     print(f"Sequence: {' → '.join('rest' if l == 0 else str(l) for l in levels)}")
#     print(f"{args.hold:.0f}s/step × {len(levels)} = ~{total_s:.0f}s")
#     print("Tip: if all I feel the same, turn DOWN the TENS unit dial.\n")

#     port = None
#     if args.ems and not args.dry_run:
#         import serial
#         print(f"Connecting {args.ems} @ {EMS_BAUD}…")
#         port = serial.Serial(args.ems, EMS_BAUD, timeout=1)
#         print(f"Waiting {EMS_BOOT_WAIT_S}s for board init…")
#         boot_end = time.time() + EMS_BOOT_WAIT_S
#         while time.time() < boot_end:
#             drain_serial(port, args.verbose)
#             time.sleep(0.05)
#         drain_serial(port, args.verbose)
#         print("Ready.")
#     elif args.dry_run:
#         print("DRY RUN.")

#     try:
#         for level in levels:
#             hold_level(
#                 port, level, channel_idx, args.hold,
#                 args.dry_run, args.verbose, use_hex, args.repeat,
#             )
#     except KeyboardInterrupt:
#         print("\nInterrupted.")
#     finally:
#         if port and not args.dry_run:
#             print(f"\nWaiting {OFF_SETTLE_S:.1f}s for channel to close…")
#             time.sleep(OFF_SETTLE_S)
#             drain_serial(port, args.verbose)
#             port.close()
#         print("Done.")


# if __name__ == "__main__":
#     main()

#!/usr/bin/env python3
"""
ems_ramp_test.py — openEMSstim perceptible range test
Uses test mode commands (1, w, q) since full command mode has parsing issues.

Perceptible range found: wiper 255 (min) → 230 (first noticeable change)
This script steps through that range in controlled increments.

Usage:
  python3 ems_ramp_test.py --dry-run
  python3 ems_ramp_test.py --ems /dev/tty.usbserial-210 --confirm
  python3 ems_ramp_test.py --ems /dev/tty.usbserial-210 --confirm --hold 6 --step 5
"""

import argparse
import time
import serial

EMS_BAUD = 19200
EMS_BOOT_WAIT_S = 12

# Perceptible wiper range — 255 = minimum, 220 = max safe strong end
WIPER_START = 255   # safe minimum — where board initializes
WIPER_END   = 220   # lower = stronger, don't go too low
DEFAULT_STEP = 5    # wiper steps per level (each w press = 1 step in firmware)
                    # we send multiple w presses to achieve larger steps


def set_wiper_position(port, current: int, target: int, dry_run: bool) -> int:
    """Move wiper from current to target by sending w (decrease) or q (increase) commands."""
    if current == target:
        return current

    if target < current:
        # Need to decrease wiper (stronger) — send 'w'
        steps = current - target
        direction = 'w'
        label = "STRONGER"
    else:
        # Need to increase wiper (weaker) — send 'q'
        steps = target - current
        direction = 'q'
        label = "weaker"

    print(f"    Moving wiper {current} → {target} ({steps} steps {label})")

    if not dry_run:
        for _ in range(steps):
            port.write(direction.encode('ascii'))
            port.flush()
            time.sleep(0.05)  # small delay between steps

    return target


def activate_channel(port, dry_run: bool) -> None:
    print("    Activating channel 1...")
    if not dry_run:
        port.write(b'1')
        port.flush()
        time.sleep(0.1)


def deactivate_channel(port, dry_run: bool) -> None:
    print("    Deactivating channel 1...")
    if not dry_run:
        port.write(b'1')
        port.flush()
        time.sleep(0.1)


def drain_serial(port, verbose: bool) -> None:
    if not verbose or port is None:
        return
    while port.in_waiting:
        line = port.readline().decode("utf-8", errors="replace").strip()
        if line:
            print(f"    [board] {line}")


def wait_with_countdown(hold_s: float, label: str) -> None:
    end = time.time() + hold_s
    last_tick = -1
    while time.time() < end:
        tick = int(end - time.time())
        if tick != last_tick:
            print(f"    … {tick + 1}s left {label}")
            last_tick = tick
        time.sleep(0.25)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Step EMS wiper through perceptible range (255→220)"
    )
    parser.add_argument("--ems", help="openEMSstim serial port e.g. /dev/tty.usbserial-210")
    parser.add_argument("--confirm", action="store_true",
                        help="Required to send to real hardware")
    parser.add_argument("--hold", type=float, default=6.0,
                        help="Seconds at each wiper level (default 6)")
    parser.add_argument("--step", type=int, default=DEFAULT_STEP,
                        help=f"Wiper step size per level (default {DEFAULT_STEP})")
    parser.add_argument("--start", type=int, default=WIPER_START,
                        help=f"Starting wiper position (default {WIPER_START} = minimum)")
    parser.add_argument("--end", type=int, default=WIPER_END,
                        help=f"Ending wiper position (default {WIPER_END}, lower = stronger)")
    parser.add_argument("--verbose", action="store_true",
                        help="Print board serial output")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview without sending commands")
    args = parser.parse_args()

    if args.end < 0 or args.end > 255:
        print("ERROR: --end must be between 0 and 255")
        return
    if args.end >= args.start:
        print("ERROR: --end must be less than --start (lower wiper = stronger stimulation)")
        return
    if args.end < 150:
        print("WARNING: wiper end below 150 may be very strong. Proceed carefully.")

    # Build ramp: start → end → start (ramp up intensity then back down)
    levels = list(range(args.start, args.end - 1, -args.step))
    # Add return ramp
    levels_down = list(range(levels[-1] + args.step, args.start + 1, args.step))
    full_sequence = levels + levels_down

    total_s = args.hold * len(full_sequence)

    print(f"\n{'DRY RUN — ' if args.dry_run else ''}openEMSstim Ramp Test")
    print(f"Port: {args.ems or 'none'}")
    print(f"Wiper range: {args.start} → {args.end} → {args.start}")
    print(f"Step size: {args.step} | Hold: {args.hold}s per level")
    print(f"Sequence: {' → '.join(str(l) for l in full_sequence)}")
    print(f"Total time: ~{total_s:.0f}s ({total_s/60:.1f} min)")
    print(f"\nREMINDER:")
    print(f"  Wiper {args.start} = MINIMUM stimulation (safe start)")
    print(f"  Wiper {args.end}   = STRONGER stimulation")
    print(f"  Press Ctrl+C at any time to stop safely\n")

    if bool(args.ems) and not args.dry_run and not args.confirm:
        print("Add --confirm to send real stimulation (or --dry-run to preview).")
        return

    port = None
    if args.ems and not args.dry_run:
        print(f"Connecting to {args.ems} @ {EMS_BAUD} baud...")
        port = serial.Serial(args.ems, EMS_BAUD, timeout=1)
        print(f"Waiting {EMS_BOOT_WAIT_S}s for board to initialize...")
        boot_end = time.time() + EMS_BOOT_WAIT_S
        while time.time() < boot_end:
            drain_serial(port, args.verbose)
            time.sleep(0.05)
        drain_serial(port, args.verbose)
        print("Board ready.\n")

    current_wiper = args.start

    try:
        # Step 1: Make sure wiper is at safe starting position
        print(f">>> Setting wiper to safe start position ({args.start})...")
        if port and not args.dry_run:
            # Send enough q presses to get to 255
            for _ in range(255):
                port.write(b'q')
                port.flush()
                time.sleep(0.02)
        print(f"    Wiper at {args.start} (minimum stimulation)\n")

        # Step 2: Activate channel
        print(">>> Activating channel 1 (at minimum intensity)...")
        activate_channel(port, args.dry_run)
        time.sleep(1.0)
        drain_serial(port, args.verbose)
        print("    Channel active. Starting ramp in 3 seconds...")
        time.sleep(3.0)

        # Step 3: Ramp through levels
        for i, target_wiper in enumerate(full_sequence):
            direction = "↓ STRONGER" if target_wiper < current_wiper else "↑ weaker"
            print(f"\n>>> Level {i+1}/{len(full_sequence)}: wiper {current_wiper} → {target_wiper} {direction}")

            current_wiper = set_wiper_position(port, current_wiper, target_wiper, args.dry_run)
            drain_serial(port, args.verbose)

            wait_with_countdown(args.hold, f"(wiper={target_wiper})")
            drain_serial(port, args.verbose)

        print(f"\n>>> Ramp complete.")

    except KeyboardInterrupt:
        print(f"\n\nInterrupted by user.")

    finally:
        # Always deactivate channel safely
        print(f"\n>>> Returning to safe state (wiper 255, channel off)...")
        if port and not args.dry_run:
            # Return wiper to 255
            for _ in range(255):
                port.write(b'q')
                port.flush()
                time.sleep(0.02)
            # Deactivate channel
            deactivate_channel(port, False)
            time.sleep(0.5)
            drain_serial(port, args.verbose)
            port.close()
        print("Done. Board is in safe state.")


if __name__ == "__main__":
    main()