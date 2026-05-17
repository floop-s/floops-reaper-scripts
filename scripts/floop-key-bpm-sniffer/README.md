# Floop Key & BPM Sniffer

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-1.0.0-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)

**Advanced Audio Key and Tempo Analysis tool for REAPER.**

---

## Overview

**Floop Key & BPM Sniffer** is an advanced audio analysis utility designed to quickly and accurately detect the musical Key and Tempo (BPM) of your audio items. It leverages a custom Dual-Resolution engine combining Spectral Flux for precise timing and Chromagram analysis for tonal recognition, all wrapped in a sleek, fully responsive interface that seamlessly adapts to any REAPER theme.



## Screenshot

<p align="center"> 
 <br> 
 <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-key-bpm-sniffer-big.png" target="_blank"> 
   <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-key-bpm-sniffer-big.png" width="450" style="border: 1px solid #202121ff;" alt="Click to zoom in"> 
 </a> 
 <br> 
 </p>
 <p align="center"> 
 <br> 
 <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-key-bpm-sniffer-small.gif" target="_blank"> 
   <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-key-bpm-sniffer-small.gif" width="450" style="border: 1px solid #202121ff;" alt="Click to zoom in"> 
 </a> 
 <br> 
 </p>



## Key Features

*   **Dual-Resolution Analysis**: Reads audio in 1024-sample blocks for accurate BPM timing and accumulates into 16384-sample blocks for high-resolution Key detection, optimizing CPU in a single pass.
*   **Key Detection (Chromagram)**: Identifies the root musical key (Major/Minor) using advanced FFT and Chroma energy profiling.
*   **Tempo Detection (BPM)**: Calculates precise BPM using Spectral Flux and autocorrelation, complete with intelligent weighting to handle unquantized live music and tape drift.
*   **Dynamic Theme Engine**: The UI automatically reads your active REAPER theme colors, calculates luminance, and procedurally generates a cohesive, accessible palette. No more hardcoded colors clashing with your setup!
*   **Responsive UI**: Elastic layout featuring dynamic text truncation for long item names and a borderless, flat-design Chroma profile chart.
*   **Mini & Full Modes**: Toggle between a compact floating widget for quick checks and a detailed full view showing the complete Chroma energy chart.
*   **Smart Docking**: Safely docks and undocks within the REAPER UI without glitching.



## Requirements

*   **REAPER v7.0** or later.
*   **ReaImGui**: "ReaScript binding for Dear ImGui" installed via ReaPack.



## Compatibility

*   **Operating Systems**:
    *   **Windows**: Fully tested and supported.
    *   **macOS / Linux**: Designed with cross-platform compatibility, but not personally tested. Feedback is welcome!



## Installation

The easiest way to install and keep the script updated is via **ReaPack**.

### Method 1: ReaPack (Recommended)

1.  **Install Prerequisites**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for and install: `ReaScript binding for Dear ImGui`.
    *   **Restart REAPER**.

2.  **Add the Repository**:
    *   Open **Extensions > ReaPack > Import Repositories...**
    *   Copy and paste this URL:
        `https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml`
    *   Click **OK**.

3.  **Install the Script**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for `Floop Key & BPM Sniffer`.
    *   Right-click > **Install**.
    *   Click **Apply**.

### Method 2: Manual Installation

1.  **Install Prerequisites**:
    *   Follow step 1 from the ReaPack method above to install `ReaImGui`.

2.  **Install the Script**:
    *   Download the script file `floop-key-bpm-sniffer.lua`.
    *   Copy to your REAPER Scripts folder (`Options > Show REAPER resource path in explorer/finder`). 

3.  **Load the Action**:
    *   Open the Actions List (`?` shortcut).
    *   Click **New Action > Load ReaScript...**
    *   Select `floop-key-bpm-sniffer.lua`.



## Usage

### 1. Basic Analysis
*   **Select an Item**: Click on any audio item in the arrangement view.
*   **Analyze**: Press the **Analyze** button (Mini Mode) or **Analyze Key** (Full Mode).
*   **Results**: The script will display the estimated Key, Confidence percentage, and BPM.

### 2. Interface Modes
*   **Mini Mode**: A compact horizontal strip showing just the essential Analyze button, Key, and BPM. Ideal for keeping open while working.
*   **Full Mode**: Expands to show the Selected Item name, detailed analysis progress, and the visual Chroma Profile chart.
*   **Toggle**: Use the `+` and `-` buttons in the top left corner to switch between modes.

### 3. Chroma Profile Chart (Full Mode)
*   Displays the energy distribution across all 12 musical notes.
*   The dominant note (root) is highlighted in green, while other notes are displayed in blue.
*   The chart scales dynamically based on the window width and height.



## Limitations & Expectations

While the custom Dual-Resolution engine is highly accurate for most music, please keep in mind that **this is an algorithmic tool, not a human ear**. 

*   **BPM Detection**: May struggle with extreme tempo fluctuations, heavy live rubato, or tracks lacking clear transients. Older recordings with significant "tape drift" (like classic rock or jazz) might yield an average mathematical BPM rather than a strict metronomic grid.
*   **Key Detection**: Complex polyphonic arrangements, heavily detuned samples, or atonal percussive material can occasionally confuse the Chromagram analysis. 
*   **Best Practice**: Use the tool as a highly educated starting point, but always trust your own ears for the final verdict!


## Changelog

### v1.0.0
* Initial Release. Features Dual-Resolution audio analysis, Spectral Flux BPM detection, Chromagram Key detection, and a dynamic Theme Engine for ReaImGui.


## Support Development

If you find my scripts useful and want to support their development, you can buy me a coffee on Ko-fi:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)


## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)

---

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See `LICENSE.txt` in the repository for details.


