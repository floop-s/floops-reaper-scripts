# Floop Multiband Transient Shaper


![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-1.1.0-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)



**3-Band Transient Shaping with up to 8x Oversampling.**

---

## Overview

**Floop Multiband Transient Shaper** is a high-performance dynamics processor written in JSFX for REAPER. It allows precise control over the attack and sustain of your audio across three independent frequency bands, ensuring punchy drums and tight mixes without introducing unwanted artifacts.

It features mastering-grade technologies including transparent crossovers, up to 8x oversampling, LUFS-based Auto-Gain, and a built-in Soft Clipper/Limiter for safety.

---

## Screenshot

<p align="center"> 
 <br> 
 <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-multiband-transient-shaper-interface.png" target="_blank"> 
   <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-multiband-transient-shaper-interface.png" width="450" style="border: 1px solid #27a086ff;" alt="Click to zoom in"> 
 </a> 
 <br> 
 </p>

---

## Key Features

* **3-Band Processing**: Independent control of Attack, Sustain, and Gain for Low, Mid, and High frequencies.
* **Pristine Audio Quality**: Up to **8x Oversampling** for alias-free processing, even with heavy saturation.
* **Transparent Crossovers**: Selectable 12dB/oct or 24dB/oct slopes with phase-corrected recombination.
* **LUFS Auto-Gain**: Automatic loudness compensation to match input and output levels (ITU-R BS.1770-4 compliant).
* **Safety Limiting**: Integrated Output Soft Clipper and Lookahead Limiter to prevent digital overs.
* **Delta Monitoring**: Listen to exactly what the plugin is adding or removing from the signal.
* **Detector Sidechain Filter**: High-Pass Filter (100Hz) for the detection circuit to prevent low-end pumping.
* **Visual Feedback**: Real-time gain reduction visualization and interactive crossover display.

---

## Requirements

* **REAPER v7.5x** or later.
* Compatible with other DAWs via **YSFX** (VST/AU wrapper for JSFX).
* **Operating Systems**: Windows (Tested). macOS and Linux should work (JSFX is cross-platform) but have not been personally tested.

---

## Installation

### Method 1: ReaPack (Recommended)

1. In REAPER, open:
   **Extensions > ReaPack > Import Repositories...**

2. Copy and paste this URL:
https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml

3. Click **OK**.

4. Then open:
   **Extensions > ReaPack > Browse Packages**

5. Search for `Floop Multiband Transient Shaper`, right-click and select **Install**, then click **Apply**.

### Method 2: Manual Installation

1. Open **REAPER**.
2. Go to **Options > Show REAPER resource path...**.
3. Open the **Effects** folder.
4. Copy `floop-multiband-transient-shaper.jsfx` into this folder (or a subfolder like `Floop`).
5. **Restart REAPER** (recommended) or press **F5** in the FX Browser.
6. In the FX Browser, search for `Floop Multiband Transient Shaper` and load it.

---

## Usage

### Interface Controls

* **Crossovers**: Drag the vertical lines in the spectrum view to adjust Low-Mid and Mid-High split points.
* **Band Controls (Low/Mid/High)**:
  * **Attack**: Boost or cut the initial transient.
  * **Sustain**: Boost or cut the tail/body of the sound.
  * **Gain**: Adjust the output level of the specific band.
  * **M/S/B Buttons**: Mute, Solo, or Bypass individual bands.
* **Global Controls**:
  * **Oversampling**: Select Off, 2x, 4x, or 8x. (Higher rates increase CPU usage and latency)
  * **Auto Gain**: Enables LUFS-based level matching.
  * **Soft Clip**: Enables output saturation to tame peaks.
  * **Delta**: Solos the difference between input and processed signal.

---

## Troubleshooting & Tips

* **Latency**: 8x Oversampling introduces latency; REAPER handles it via PDC (Plugin Delay Compensation).
* **CPU Usage**: 8x Oversampling is heavy; 2x or 4x recommended for real-time playback.
* **Audio Differences**: Use **Delta** monitoring to hear exactly what the plugin changes.
  - *Will this work in other DAWs?*  
    Yes, via YSFX wrapper (VST/AU), though full integration is only in REAPER.

---

## Changelog

### v1.1.0
* Improved Attack/Sustain knob resolution with cubic mapping for finer control at low settings.
* Fixed phase cancellation notch in Analog LR2 Crossover mode via Allpass delay compensation.
* Improved Oversampling high-end response with steeper polyphase transition bands.
* Corrected K-Weighting HP filter to 38Hz per ITU-R BS.1770 standard.
* Fixed Output Gain and Wet/Dry staging order; fixed crossover mode state reset logic.

### v1.0.0
* Initial Release.

---

## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)

---

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See `LICENSE.txt` in the repository for details.

---


