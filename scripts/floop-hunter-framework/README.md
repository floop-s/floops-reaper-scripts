# Floop Hunter Framework

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-1.2.1-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)

**Automatic vocal cleanup for REAPER, detects and reduces sibilance, plosives, and breaths with precision volume automation.**

## Overview

**Floop Hunter Framework** is an advanced, multi-module automation writer designed to automatically clean up vocal recordings. It analyzes the selected vocal tracks to selected vocal tracks, detects artifacts (Sibilants, Plosives, and Breaths) using source-specific profiles, and writes precise volume automation to reduce them non-destructively.

By utilizing a unified JSFX plugin, it ensures that overlapping detections (e.g., a breath colliding with a plosive) are merged cleanly, preventing double-automation and keeping your envelope perfectly organized.

This script is designed as a *workflow accelerator and an interactive editor*, not a magical 100% accurate one-click solution. Automated detection is never perfect. Its purpose is to rapidly find artifact candidates and provide you with a visual editor to quickly confirm, delete, or adjust the automation, reducing the amount of manual editing required. Treat the script's output as a highly advanced starting point. It does the heavy lifting, but your ears remain the final judge. Always review the automation before committing to a mix.



## Overview & Media

<p align="center"> 
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-hunter%20framework.gif" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-hunter%20framework.gif" width="700" style="border: 1px solid #27a086ff;" alt="Floop Hunter Framework Action">
  </a>
</p>

<p align="center">
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-hunter-framework-ess.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-hunter-framework-ess.png" width="32%" style="border: 1px solid #27a086ff;" alt="Ess Hunter">
  </a>
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-hunter-framework-plosive.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-hunter-framework-plosive.png" width="32%" style="border: 1px solid #27a086ff;" alt="Plosive Hunter">
  </a>
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-hunter-framework-breath.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-hunter-framework-breath.png" width="32%" style="border: 1px solid #27a086ff;" alt="Breath Hunter">
  </a>
</p>

## Key Features

*   **Three Dedicated Hunters**:
    *   **Ess Hunter**: Targets harsh high-frequency sibilance ("S", "Sh").
    *   **Plosive Hunter**: Detects low-frequency transient bursts ("P", "B" pops).
    *   **Breath Hunter**: Intelligently identifies inhale/exhale gaps using adaptive sliding-context envelopes.
*   **Source Profiles**: Optimized detection thresholds tailored for Female, Male, Spoken, or Rap vocals.
*   **Unified Conflict Resolution**: "Maximum reduction wins" strategy prevents overlapping envelopes from stacking destructively.
*   **Asynchronous Engine**: Background chunked processing keeps the REAPER UI fluid even during heavy 5-minute vocal scans.
*   **Interactive Visualizer**: Fully interactive waveform display. Zoom, pan, adjust individual segment gains, resize boundaries,
     delete false positives, or draw custom segments manually (Ctrl + Right-Click Drag).
*   **Live Edit & Auto Scan**: Tweak thresholds and watch the detection update instantly. With "Live Edit" enabled, any slider change automatically rewrites the envelope on the timeline.
*   **Non-Destructive JSFX Integration**: Installs a lightweight custom JSFX plugin ("Floop Hunter.jsfx") to handle pure gain reduction without touching native item volumes. It is **automatically placed** at the start of the FX chain or immediately after virtual instruments.
*   **Envelope Targets & Shapes**: Choose to write automation to the Track FX or directly to the Take FX, and customize the envelope point shapes (Linear, Bezier, Slow Start/End, etc.). Automations are firmly attached to media items and move with them.
*   **Preset Management**: Save, load, and manage custom thresholds across all three hunters independently.

## Requirements

*   **REAPER v7.6x** or later.
*   **ReaImGui**: "ReaScript binding for Dear ImGui" installed via ReaPack.

## Compatibility Note
![Platform](https://img.shields.io/badge/Tested-Windows-yellow) ![Platform](https://img.shields.io/badge/macOS%20%2F%20Linux-Untested-orange)

This script has been extensively developed and tested on **Windows**. It has been built with cross-platform compatibility in mind and should theoretically work perfectly on **macOS** and **Linux**, but I cannot fully guarantee it at this time. Feedback from Mac and Linux users is highly appreciated!



## Usage


## Installation
The easiest way to install and keep the script updated is via **ReaPack**.

### Method 1: ReaPack (Recommended)

1.  **Install Prerequisites**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for and install:
        *   `ReaScript binding for Dear ImGui`
    *   **Restart REAPER**.

2.  **Add the Repository**:
    *   Open **Extensions > ReaPack > Import Repositories...**
    *   Copy and paste this URL:
        https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
    *   Click **OK**.

3.  **Install the Script**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for `Floop Hunter Framework`.
    *   Right-click > **Install**.
    *   Click **Apply**.

### Method 2: Manual Installation

1.  **Install ReaImGui**:
    *   Go to **Extensions > ReaPack > Browse Packages**.
    *   Search for and install `ReaImGui: ReaScript binding for Dear ImGui`.
    *   Restart REAPER.
2.  **Install the Script**:
    *   Copy the entire `Floop Hunter Framework` folder to your REAPER Scripts folder.
    *   Path: `REAPER > Options > Show REAPER resource path > Scripts`.
3.  **Load the Action**:
    *   Open the **Actions List** (`?`).
    *   Click **New Action > Load ReaScript...**.
    *   Select `floop-hunter-framework.lua`.
---


## Quick Start 

1.  **Select** a vocal item or track in REAPER.
2.  **Launch** the Floop Hunter Framework from the Actions List.
3.  **Choose a Profile**: Select Female, Male, Spoken, or Rap (crucial for correct frequency detection).
4.  **Analyze**: Enable the hunters you need (Ess, Plosive, Breath) and hit Analyze. The script will automatically add the `Floop Hunter.jsfx` plugin to process gain reduction.
5.  **Routing & Shapes**: Choose whether the automation should be written to the **Track FX** or **Take FX**, and pick your preferred envelope shape (e.g., Slow Start/End).
6.  **Apply Unified**: Click "Apply Unified Reduction" to write the automation envelope.
7.  **Listen Back**: Always review the generated automation.
8.  **Fine-Tuning**: Enable **Auto Scan** to re-detect instantly when changing selection, and **Live Edit** to automatically rewrite the envelope on the timeline whenever you adjust a slider. Use the **Visualizer** to draw custom points, resize edges, or delete false positives.






## Changelog

### v1.2.1
* **Bug Fix**: Fixed a critical bug where Live Edit would destructively wipe out other active Hunters' envelopes. Live Edit now properly utilizes the Unified Reduction engine.

### v1.2.0
* **Non-Destructive State Management**: Introduced a robust `P_EXT` state memory system that allows applying multiple Hunters sequentially on the same clip without erasing previous automations. Overlapping Gain interventions (e.g., Ess + Breath) are intelligently resolved using a "strongest-wins" logic.
* **Continuous Filter Processing**: Redesigned the JSFX High-Pass Filter for Plosives to be "Always-On", completely eliminating zipper noises and phase-jump clicks during rapid envelope changes.
* **Geometric Envelope Anchoring**: Envelopes are now strictly anchored to their default values at the exact clip boundaries, preventing visual and mathematical "sloping" from legacy points outside the item.

### v1.1.0
* **Major Overhaul**: Complete rewrite of the Plosive Hunter and Breath Hunter DSP engines for extreme accuracy.
* **Redefined Logic**: Significant optimization and redefinition of the Ess Hunter.
* **Acoustic Profiles**: Introduced source-specific Acoustic Profiles (Female, Male, Spoken, Rap) combined with dynamic Macro-Sliders, replacing the old rigid preset system.
* **Dual-Envelope Routing (JSFX Upgrade)**: Upgraded the companion JSFX and routing engine to completely separate Plosives (which now use a dedicated High-Pass Filter envelope) from Ess/Breaths (which use a Gain envelope). This eliminates destructive overlaps between fundamentally different artifact treatments.
* **Custom Presets**: Introduced a robust User Preset save/load system via Reaper ExtState.
* **UI Optimizations**: Refined the waveform visualizer controls and reorganized the interface layout for maximum screen efficiency.

### v1.0.0
* Initial Release.



## Support

If this script saves you time, a coffee is always appreciated. 

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)


## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)



## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See the `LICENSE.txt` file in the main repository for details.