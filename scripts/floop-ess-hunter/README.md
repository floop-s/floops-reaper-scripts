# Floop Ess Hunter

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-1.2.0-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)

**Automatic vocal cleanup for REAPER. Detects and reduces harsh sibilance ("s", "sh", "ch") with precision volume automation.**

## Overview

**Floop Ess Hunter** is an advanced automation writer designed to automatically clean up sibilant sounds in vocal recordings. It listens to selected vocal tracks, detects artifacts using source-specific frequency analysis, and writes precise volume automation to reduce them non-destructively.

By writing envelope points only on detected segments, it preserves the natural dynamics of the surrounding performance, saving you hours of tedious manual clicking and zooming. Treat the script's output as a highly advanced starting point. It does the heavy lifting, but your ears remain the final judge.

## Screenshot


 <p align="center"> 
 <br> 
 <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-ess-hunter-advanced.png" target="_blank"> 
   <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-ess-hunter-advanced.png" width="450"  alt="Click to zoom in"> 
 </a> 
 <br> 
 </p>

## Key Features

*   **Zero-Allocation DSP Engine**: Blazing fast Single-Pass analysis focusing on targeted frequencies.
*   **Real-time "Live Edit"**: Instantly see and hear segment boundaries and volume changes without full re-analysis.
*   **Adaptive Threshold**: Uses band/wide spectral ratio for robust detection.
*   **Precise Editing**: Writes envelope points only on sibilant segments.
*   **Non-Destructive**: Supports Track Volume, Pre-FX Volume, and Take Volume envelopes.
*   **Safe Workflow**: Automatically wipes overlapping segments cleanly and integrates with REAPER's Undo blocks.
*   **Interactive Visual Preview**: Zoom/pan, resize segments, and tweak individual segment gain directly on the waveform.
*   **Presets**: Built-in presets for Speech, Soft Singing, Aggressive Singing, plus user custom presets.

## Requirements

*   **REAPER v7.48** or later.
*   **ReaImGui**: "ReaScript binding for Dear ImGui" installed via ReaPack.

## Installation

The easiest way to install and keep the script updated is via **ReaPack**.

### Method 1: ReaPack (Recommended)

1.  **Install Prerequisites**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for and install:
        *   `ReaScript binding for Dear ImGui`
        *   `SWS/S&M Extension`
    *   **Restart REAPER**.

2.  **Add the Repository**:
    *   Open **Extensions > ReaPack > Import Repositories...**
    *   Copy and paste this URL:
        https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
    *   Click **OK**.

3.  **Install the Script**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for `Floop Ess Hunter`.
    *   Right-click > **Install**.
    *   Click **Apply**.

### Method 2: Manual Installation

1.  **Install ReaImGui**:
    *   Go to **Extensions > ReaPack > Browse Packages**.
    *   Search for and install `ReaImGui: ReaScript binding for Dear ImGui`.
    *   Restart REAPER.
2.  **Install the Script**:
    *   Copy the `Floop Ess Hunter` folder (or just the `.lua` file) to your REAPER Scripts folder.
    *   Path: `REAPER > Options > Show REAPER resource path > Scripts`.
3.  **Load the Action**:
    *   Open the **Actions List** (`?`).
    *   Click **New Action > Load ReaScript...**.
    *   Select `Floop Ess Hunter.lua`.

## Quick Start

1.  Select one or more **vocal items** in your project.
2.  Run **Floop Ess Hunter** from the Actions List.
3.  Click **Analyze and apply** to analyze and write envelope points.
4.  Adjust parameters under **Advanced Setting** if needed.
5.  Use **Clear segments on selection** to remove segments.

> **Tip**: You can target the **Pre-FX Volume** envelope (recommended) or the standard **Track Volume** envelope. You can also target the **Take Volume** envelope. The script ensures the chosen envelope is visible.

## Parameters (Fine Tuning)

### Analysis
*   **Target Freq**: Frequency cutoff for sibilance detection (High-Pass Filter) (default 6000 Hz).
*   **Threshold**: Minimum signal level for sibilance detection (default -40.0 dB).
*   **Sibilance Sens.**: Master sensitivity control adjusting internal ZCR and ratio thresholds (default 50.0 %).

### Detection
*   **Min Length**: Minimum duration for a valid sibilant segment (default 20 ms).
*   **Max Gap**: Maximum gap within a sibilant segment before splitting (default 20 ms).

### Segments
*   **Pre / Post Ramp**: Fade-in/out edges (default 2 / 10 ms).
*   **Reduction**: Attenuation applied to segments (default 4.0 dB).
*   **Envelope Target**: Choose between Track Volume, Track Pre-FX, or Take Volume.

## Troubleshooting

*   **"ReaImGui not found"**: Install via ReaPack and restart REAPER.
*   **Envelope not visible**: The script tries to show it, but you can manually check Track Envelopes.
*   **No segments detected**:
    *   Lower **Threshold** (more negative).
    *   Increase **Sibilance Sens.**.
    *   Decrease **Target Freq**.
    *   Reduce **Min Length**.
*   **Performance**: Analysis is fully asynchronous and will not freeze the UI, but large items may take a moment to scan.

## Changelog

### v1.2.0 (2026-06-25)
*   **UI/UX**: Complete overhaul of the interface with custom toggles.
*   **UI/UX**: Refactored analysis engine to run asynchronously, preventing UI freezes on long audio items and adding a progress bar.
*   **Feature**: Added Context-Aware Right-Click Reset for all sliders, falling back to the active preset values.
*   **Feature**: Optimized Live Edit volume sync. Modifying the global Reduction slider now updates segments in real-time.
*   **DSP**: Switched from multi-band BPF to a zero-allocation HPF (Butterworth) engine for faster and more coherent sibilance detection.
*   **Clean-up**: Removed obsolete options to simplify the interface.
*   **Fix**: Corrected `start_offs` and `playrate` calculations to perfectly align Take Envelopes on trimmed items.
*   **Fix**: Resolved segment dropping at the rightmost edge of media items.
*   **Fix**: Fixed incorrect envelope point values by respecting track envelope scaling mode (Fader/Amplitude).

### v1.1.2 (2026-02-20)
*   **Fix**: Fixed cumulative volume reduction when sibilant segments overlap.
*   **Fix**: Fixed incorrect envelope point values by respecting track envelope scaling mode (Fader/Amplitude).

### v1.1.1 (2026-02-15)
*   **Stability**: Improved envelope visibility when applying from preview and during Live Edit.
*   **Control**: Segment gain handles now support live update when Live Edit is enabled.
*   **Analysis**: Median ratio clamping hardened for extremely sibilant or short clips.

### v1.1.0 (2026-01-08)
*   **New Feature**: Support for split clips and items not starting at timeline zero.
*   **New Feature**: Interactive handles for manual segment resizing.
*   **New Feature**: Per-segment volume adjustment via vertical drag (0–24 dB reduction).
*   **UI**: Improved waveform display alignment for offset items.
*   **Fix**: "Analyze and Apply" logic aligned with take-relative time for accurate envelope placement.
*   **Fix**: Resolved segment edge resizing conflicts with volume drag.

### v1.0.0 (2025-10-31)
*   Initial public release.
*   Sibilance detection pipeline with envelope writing.
*   Quickselect O(n) optimization.
*   Timing correction for playback rates.
*   Undo blocks integration.

## Support

If this script saves you time, a coffee is always appreciated. 

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)

## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See the `LICENSE.txt` file in the main repository for details.
