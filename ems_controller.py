#!/usr/bin/env python3
import sys
sys.path.insert(0, "apps/python")

import configparser
from pyEMS.EMSCommand import ems_command

CALIBRATION_FILE  = "apps/python/calibration.ems"
SENSORY_THRESHOLD = 0.15
RAMP_STEP         = 5
DEFAULT_DURATION  = 500

def load_calibration(filepath):
    config = configparser.ConfigParser()
    config.read(filepath)
    return {
        "channel1_ceiling": int(config["intensity"]["channel1"]),
        "channel2_ceiling": int(config["intensity"]["channel2"]),
        "preset_duration":  int(config["presets"]["preset_stimulation_duration"]),
    }

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

if __name__ == "__main__":
    cal = load_calibration(CALIBRATION_FILE)
    print("Calibration loaded:", cal)
    test_activations = [0.0, 0.1, 0.2, 0.4, 0.6, 0.8, 1.0, 0.5, 0.0]
    print(f"\n{'activation':>12}  {'ch':>4}  {'command':>20}")
    print("-" * 42)
    for a in test_activations:
        for ch in [1, 2]:
            cmd = activation_to_command(a, ch, cal)
            print(f"{a:>12.2f}  {ch:>4}  {cmd if cmd else 'NO STIM':>20}")
