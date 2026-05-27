import sys
sys.path.insert(0, "../openEMSstim/apps/python")
import csv, configparser
from pyEMS.EMSCommand import ems_command

CALIBRATION_FILE = "calibration.ems"
SENSORY_THRESHOLD = 0.15
RAMP_STEP = 5
DEFAULT_DURATION = 500

def load_calibration(filepath):
    config = configparser.ConfigParser()
    config.read(filepath)
    return {
        "channel1_ceiling": int(config["intensity"]["channel1"]),
        "channel2_ceiling": int(config["intensity"]["channel2"]),
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

cal = load_calibration(CALIBRATION_FILE)
print(f"Calibration: {cal}")
print(f"\n{'time_s':>10}  {'activation':>10}  {'command':>20}")
print("-" * 46)

with open("session_20260526_004927.csv") as f:
    for row in csv.DictReader(f):
        t = float(row["time_s"])
        norm = float(row["activation"])
        cmd = activation_to_command(norm, 1, cal)
        if cmd:
            print(f"{t:>10.3f}  {norm:>10.4f}  {cmd:>20}")
