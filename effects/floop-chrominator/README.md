# Floop Chrominator
![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-2.1.0-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)

**Stereo Analog Saturator for Reaper.**


## Overview

**Floop Chrominator** is a JSFX effect for REAPER that emulates stereo "analog" saturation with five selectable modes (Soft, Even, Clip, Warm, Odd). It adds warmth, presence, and character to tracks and buses, from subtle color to heavier drive, featuring oversampling, filters, tilt EQ, auto‑gain, and smooth parameter transitions.

## Screenshot


<p align="center"> 
 <br> 
 <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-chrominator-2.png" target="_blank"> 
   <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-chrominator-2.png" width="350" alt="click to zoom in"> 
 </a> 
 <br> 
</p>


## Key Features

*   **Five Saturation Modes**: Soft, Even, Clip, Warm, Odd.
*   **Oversampling**: 1x, 2x, 4x via high-performance 12th-order Polyphase IIR.
*   **Filters**: Low Cut and High Cut with selectable slope (Gentle/Sharp).
*   **Head Bump**: Low-frequency reinforcement near the cutoff.
*   **Tilt EQ**: Balances lows and highs after saturation.
*   **Auto-Gain**: Matches loudness between dry and wet signals.
*   **Smooth Transitions**: Glide and crossfade on control changes to prevent clicks.
*   **DPI-Aware UI**: Scales buttons, knobs, and labels with window size/DPI.

## Requirements

*   **REAPER v7.00** or later.
*   Tested on Windows 10/11.

## Installation
The easiest way to install and keep the script updated is via **ReaPack**.

### Method 1: ReaPack (Recommended)


1.  **Add the Repository to ReaPack**:
    *   Open **Extensions > ReaPack > Import Repositories...**
    *   Copy and paste this URL:
        https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
    *   Click **OK**.

3.  **Install the Script**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for `Floop Chrominator`.
    *   Right-click > **Install**.
    *   Click **Apply**.

### Method 2: Manual Installation

1.  **Open REAPER**.
2.  Go to **Options > Show REAPER resource path...**.
3.  Enter the **Effects** folder.
4.  Copy the `Floop Chrominator.jsfx` file into this folder.
5.  **Restart REAPER** (recommended) or press "F5" in the FX Browser.
6.  In the FX Browser, search for "Floop Chrominator" and load it on a track.

## Usage

1.  Add **Floop Chrominator** to a track or bus.
2.  Select a **Mode**:
    *   **Soft**: Smooth tape-style saturation.
    *   **Even**: Asymmetric clipping, 2nd harmonic richness.
    *   **Clip**: Gritty, slightly asymmetric clipping.
    *   **Warm**: Tube-style massive even harmonics.
    *   **Odd**: Aggressive, perfectly symmetric, pure odd harmonics.
3.  Adjust **Core Controls**:
    *   **Drive**: Saturation amount (0–10).
    *   **Tone (Tilt)**: Balance lows/highs (-1 to +1).
    *   **Mix**: Parallel blend (0–100%).
    *   **Output**: Final level (-24 to +24 dB).
4.  **Fine-tune**:
    *   **Punish**: +20 dB boost before waveshaper.
    *   **Bump**: Emphasize low-cut region.
    *   **Oversampling**: Enable for high drive settings to reduce aliasing.

## Troubleshooting

*   **No loudness change with Auto-Gain**: The Auto-Gain algorithm calculates compensation directly from the Drive and Punish settings. It applies a gentle curve to preserve low-end energy during heavy clipping, so extreme fuzz settings will still sound subjectively louder and denser.
*   **Clicks when changing modes**: The script uses crossfades to prevent this, but extreme CPU load might cause dropouts.
*   **High CPU usage**: "HQ" Oversampling is intensive; use standard oversampling or disable it for real-time monitoring if needed.

## Changelog

### v2.1.0

* **Restored V1 saturation tone** with strict mathematical bounds to prevent wavefolding noise.
* **Fixed DC thump/pop** when engaging Punish via independent slew-rate limiting.
* **Improved Auto-Gain** response under heavy clipping to preserve low-end bass energy.
* **Removed obsolete HQ button** as Polyphase IIR handles all oversampling optimally.

### v2.0.0

**Major Update (DSP & UI Overhaul)**
* **Core DSP Engine (Zero-Delay):** Complete replacement of the filter architecture (Low Cut, High Cut, Tilt EQ, Bump). The plugin now utilizes SVF (State Variable Filter) and TPT (Topology Preserving Transform) topologies, ensuring absolute phase stability and entirely eliminating "zipper" noise during parameter sweeps.
* **Math-Accurate Saturation Models:** Completely rewritten formulas for all 5 distortion engines (Soft, Even, Clip, Warm, Odd). Solved all volume drop issues: there is now strict internal DC offset compensation and perfect Unity Gain when Drive is at 0.
* **Polyphase IIR Oversampling:** The legacy FIR anti-aliasing system has been replaced by a high-performance 12th-order Polyphase IIR engine (2x and 4x). It guarantees steeper transitions against aliasing while keeping transients clean and defined without digital ringing.
* **Analog Drift (TMT):** Introduced Tolerance Modeling Technology. A subtle virtual analog tolerance (0.5% - 0.8%) is now applied independently to the Left and Right channels, simulating real hardware imperfections and providing a more organic stereo image.
* **CPU Optimization (Fast Math):** Removed heavy exponential calculations from the main per-sample audio block. The plugin is now exceptionally CPU-friendly and can be easily used across dozens of tracks in a mix.
* **GUI Modernization:** Fully redesigned user interface. Features a new "Soft Dark" theme, illuminated Value Arcs on knobs with standard 7-to-5 hardware excursion, flat buttons, and logical color-coding (Amber for saturation, Green for filters and utility) for immediate visual feedback. Fixed default Mix level to 100%.

### v1.1.0

*   Bug fixes and improvements.
*   Oversampling options: 1x, 2x, 4x with FIR anti-aliasing (HQ 17-tap).

### v1.0.0
* Initial release.
* Current release with scalable UI and 5 saturation modes.


## Support Development

If you find my scripts useful and want to support their development, you can buy me a coffee on Ko-fi:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)

## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See the `LICENSE.txt` file in the main repository for details.
