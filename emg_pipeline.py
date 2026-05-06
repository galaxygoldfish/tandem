#!/usr/bin/env python3
"""Simple EMG -> TENS processing pipeline for CSV data.

Usage:
  python emg_pipeline.py --input capture.csv --output out.csv

This script is designed for Backyard Brains / SpikerShield EMG CSV data.
It supports both:
  - recorded CSV output from the Tandem app, where the signal column is already
    rectified millivolts
  - raw ADC-count CSV data from the hardware, when run with --raw-counts

The pipeline is intentionally simple and explainable:
  1) Convert raw ADC counts to mV (only if --raw-counts is used).
  2) Bandpass filter to remove drift and high-frequency noise.
  3) Rectify and smooth to form an envelope.
  4) Define a resting baseline and MVC window.
  5) Normalize to a 0-1 score.
  6) Map that score into a TENS amplitude parameter.
"""

import argparse
import csv
import math
from pathlib import Path

try:
    import numpy as np
    from scipy.signal import butter, filtfilt
    from matplotlib import pyplot as plt
except ImportError:
    np = None
    butter = None
    filtfilt = None
    plt = None


def load_csv(path):
    """Load a CSV file with timestamp_ms and signal columns.
    
    Args:
        path: File path to CSV input.
    
    Returns:
        (timestamps, values): Two numpy arrays of timestamps (ms) and signal values.
    """
    timestamps = []
    values = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)  # Skip header row
        for row in reader:
            if not row or len(row) < 2:
                continue
            try:
                timestamps.append(float(row[0]))
                values.append(float(row[1]))
            except ValueError:
                continue
    return np.array(timestamps), np.array(values)


def count_to_millivolts(raw_data, adc_ref=5.0, adc_bits=10, gain=900.0):
    """Convert raw ADC counts to millivolts using SpikerShield calibration.
    
    SpikerShield parameters:
    - 5V reference voltage
    - 10-bit ADC (0-1023 counts)
    - 900x preamplifier gain
    
    Args:
        raw_data: numpy array of raw ADC counts.
        adc_ref: ADC reference voltage (V).
        adc_bits: ADC resolution (bits).
        gain: Preamplifier gain.
    
    Returns:
        Millivolt values (numpy array).
    """
    volts_per_count = adc_ref / (2 ** adc_bits - 1)
    return raw_data * volts_per_count * 1000.0 / gain


def bandpass_filter(signal, fs, lowcut, highcut, order=4):
    """Apply Butterworth bandpass filter to remove drift and noise.
    
    Standard EMG bandpass: 20-450 Hz removes:
    - DC drift and motion artifacts (< 20 Hz).
    - High-frequency noise and interference (> 450 Hz).
    
    Args:
        signal: Input signal (numpy array).
        fs: Sampling rate (Hz).
        lowcut: Low cutoff frequency (Hz).
        highcut: High cutoff frequency (Hz).
        order: Filter order (default 4).
    
    Returns:
        Filtered signal (numpy array).
    """
    if butter is None or filtfilt is None:
        raise RuntimeError("scipy is required for filtering. Install scipy.")
    nyquist = 0.5 * fs
    low = lowcut / nyquist
    high = highcut / nyquist
    b, a = butter(order, [low, high], btype="band")
    return filtfilt(b, a, signal)  # Zero-phase filtering (forward + backward)


def moving_average(signal, window_samples):
    if window_samples < 1:
        return signal
    kernel = np.ones(window_samples) / window_samples
    return np.convolve(signal, kernel, mode="same")


def envelope(signal, fs, window_ms=50):
    """Create envelope by rectifying and smoothing the signal.
    
    Rectification converts oscillating EMG into a control signal.
    
    Args:
        signal: Filtered EMG signal (numpy array).
        fs: Sampling rate (Hz).
        window_ms: Smoothing window (default 50 ms).
    
    Returns:
        Envelope signal (numpy array).
    """
    rectified = np.abs(signal)  # Rectify: take absolute value
    window_samples = max(1, int(window_ms * 0.001 * fs))
    return moving_average(rectified, window_samples)


def clamp(x, minimum=0.0, maximum=1.0):
    return max(minimum, min(maximum, x))


def normalize_signal(env, baseline, mvc, floor=0.0, ceiling=1.0):
    """Normalize envelope using baseline and MVC (user-specific calibration).
    
    Standard EMG normalization method used in rehabilitation research.
    Makes output independent of electrode placement and skin impedance.
    
    Args:
        env: Envelope signal (numpy array).
        baseline: Resting baseline level (mV).
        mvc: Maximum voluntary contraction level (mV).
        floor, ceiling: Clipping bounds (default [0, 1]).
    
    Returns:
        Normalized signal where 0=rest and 1=MVC (numpy array).
    """
    range_val = mvc - baseline
    if range_val <= 0:
        return np.zeros_like(env)
    normalized = (env - baseline) / range_val
    return np.clip(normalized, floor, ceiling)


def map_to_tens(normed, min_level=0.0, max_level=1.0, exponent=1.8):
    """Map normalized EMG to TENS output using power law.
    
    Exponent > 1 creates gentle response at low levels, steeper ramp at high levels.
    Prevents small arm movements from causing sudden large stimulation jumps.
    Exponent 1.8 is standard in proportional FES/TENS control.
    
    Args:
        normed: Normalized EMG [0, 1] (numpy array).
        min_level, max_level: Output range (default [0, 1]).
        exponent: Power law exponent (default 1.8).
    
    Returns:
        Mapped TENS output (numpy array).
    """
    return min_level + (max_level - min_level) * np.power(normed, exponent)


def compute_window_value(timestamps, data, start_ms, end_ms, mode="mean"):
    """Extract a statistic from a time window.
    
    Used to compute baseline (mean of quiet period) and MVC (95th percentile of flex).
    
    Args:
        timestamps: Time array (ms).
        data: Data array.
        start_ms, end_ms: Time window (ms).
        mode: "mean", "max", "median", or "percentile".
    
    Returns:
        Computed statistic (float) or NaN if window is empty.
    """
    mask = (timestamps >= start_ms) & (timestamps <= end_ms)
    section = data[mask]
    if len(section) == 0:
        return float("nan")
    if mode == "mean":
        return np.mean(section)
    if mode == "max":
        return np.max(section)
    if mode == "median":
        return np.median(section)
    if mode == "percentile":
        return np.percentile(section, 95)  # 95th percentile is more robust than max
    return float("nan")


def save_output(path, timestamps, raw, filtered, env, normed, tens):
    """Save all processing stages to a CSV file for inspection and analysis.
    
    Args:
        path: Output CSV file path.
        timestamps, raw, filtered, env, normed, tens: Signal arrays at each pipeline stage.
    """
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp_ms", "raw", "filtered_mV", "envelope_mV", "normalized", "tens_level"])
        for t, r, fval, e, n, tv in zip(timestamps, raw, filtered, env, normed, tens):
            writer.writerow([f"{t:.1f}", f"{r:.6f}", f"{fval:.6f}", f"{e:.6f}", f"{n:.6f}", f"{tv:.6f}"])


def plot_results(timestamps, raw, filtered, env, normed, tens, output_path=None):
    """Create a 3-panel plot showing all processing stages.
    
    Panel 1: Raw vs. bandpass filtered signal.
    Panel 2: Rectified and smoothed envelope.
    Panel 3: Normalized strength and mapped TENS output.
    
    Args:
        timestamps, raw, filtered, env, normed, tens: Signal arrays.
        output_path: Optional file path to save the plot (PNG).
    """
    if plt is None:
        return
    fig, axs = plt.subplots(3, 1, figsize=(10, 9), sharex=True)
    
    # Panel 1: Raw and filtered
    axs[0].plot(timestamps, raw, label="raw (mV)")
    axs[0].plot(timestamps, filtered, label="filtered", alpha=0.8)
    axs[0].legend()
    axs[0].set_ylabel("mV")
    axs[0].set_title("Raw and Filtered EMG")

    # Panel 2: Envelope
    axs[1].plot(timestamps, env, label="envelope", color="#2a6f97")
    axs[1].set_ylabel("mV")
    axs[1].set_title("Rectified + Smoothed Envelope")

    # Panel 3: Normalized and TENS output
    axs[2].plot(timestamps, normed, label="normalized", color="#217a36")
    axs[2].plot(timestamps, tens, label="tens output", color="#b55122")
    axs[2].set_ylabel("unitless")
    axs[2].set_xlabel("time (ms)")
    axs[2].legend()
    axs[2].set_title("Normalized EMG and TENS Mapping")

    fig.tight_layout()
    if output_path:
        fig.savefig(output_path, dpi=150)
    plt.show()


def parse_args():
    parser = argparse.ArgumentParser(description="EMG -> TENS processing pipeline")
    parser.add_argument("--input", required=True, help="Input CSV of timestamp_ms,signal")
    parser.add_argument("--output", default="emg_pipeline_output.csv", help="Output CSV path")
    parser.add_argument("--plot", default="emg_pipeline_plot.png", help="Optional plot path")
    parser.add_argument("--fs", type=float, default=1000.0, help="Sampling rate in Hz")
    parser.add_argument("--lowcut", type=float, default=20.0, help="Low cutoff frequency for bandpass")
    parser.add_argument("--highcut", type=float, default=450.0, help="High cutoff frequency for bandpass")
    parser.add_argument("--baseline-start", type=float, default=0.0, help="Baseline window start in ms")
    parser.add_argument("--baseline-end", type=float, default=2000.0, help="Baseline window end in ms")
    parser.add_argument("--mvc-start", type=float, default=2000.0, help="MVC window start in ms")
    parser.add_argument("--mvc-end", type=float, default=5000.0, help="MVC window end in ms")
    parser.add_argument(
        "--raw-counts",
        action="store_true",
        help="Treat input signal column as raw ADC counts; otherwise assume signal is already in mV",
    )
    return parser.parse_args()


def main():
    """Main entry point: load CSV, process through pipeline, save results and plot."""
    args = parse_args()
    if np is None:
        raise RuntimeError("Install numpy, scipy, and matplotlib to run this pipeline: pip install numpy scipy matplotlib")

    # Load input CSV
    timestamps, v = load_csv(args.input)
    
    # Convert ADC counts to mV if raw hardware data
    if args.raw_counts:
        raw_mV = count_to_millivolts(v)
    else:
        raw_mV = v

    # Process through the complete pipeline
    filtered = bandpass_filter(raw_mV, args.fs, args.lowcut, args.highcut)
    env = envelope(filtered, args.fs, window_ms=50)
    baseline = compute_window_value(timestamps, env, args.baseline_start, args.baseline_end, mode="mean")
    mvc = compute_window_value(timestamps, env, args.mvc_start, args.mvc_end, mode="percentile")
    normed = normalize_signal(env, baseline, mvc)
    tens = map_to_tens(normed, min_level=0.0, max_level=1.0, exponent=1.8)

    # Print calibration results
    print(f"Baseline mean = {baseline:.6f} mV")
    print(f"MVC 95th percentile = {mvc:.6f} mV")
    print("Normalized range:", normed.min(), normed.max())

    # Save output and generate visualization
    save_output(args.output, timestamps, raw_mV, filtered, env, normed, tens)
    if plt is not None:
        plot_results(timestamps, raw_mV, filtered, env, normed, tens, output_path=args.plot)


if __name__ == "__main__":
    main()
