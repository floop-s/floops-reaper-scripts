# Floop Groove-A-Thor

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-1.1.0-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)

**Transfer rhythmic feel between any Audio or MIDI items in REAPER extract groove, inject swing, generate patterns from scratch.**

---

## Overview

**Floop Groove-A-Thor** is a comprehensive groove management utility designed to bridge the gap between "feel" and "grid". It allows you to extract the rhythmic feel (timing and velocity) from any Audio or MIDI source and apply it to any target item (Audio or MIDI) with precision.

Beyond simple quantization, Groove-A-Thor offers a robust **Visualizer**, a **Groove Library** for storing your favorite feels, and a **Procedural Groove Generator** for creating unique rhythms from scratch.

---

## Overview & Media


<p align="center">
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-groove-a-thor-audio.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-groove-a-thor-audio.png" width="32%" style="border: 1px solid #27a086ff;" alt="Audio">
  </a>
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-groove-a-thor-midi.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-groove-a-thor-midi.png" width="32%" style="border: 1px solid #27a086ff;" alt="Plosive">
  </a>
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-groove-a-thor-generator.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-groove-a-thor-generator.png" width="32%" style="border: 1px solid #27a086ff;" alt="Breath">
  </a>
</p>

---

## Key Features

*   **Groove Extraction**: Analyze Audio (transients) or MIDI items to capture precise timing deviations and velocity dynamics.
*   **Phase Coherent Mode**: Automatically align multi-track drum stems using a single master guide to preserve phase relationships.
*   **Groove Injection**: Apply extracted grooves to any target item (MIDI or Audio) with adjustable intensity (0-100%).
*   **Advanced Visualizer**:
    *   **LOCKED Mode**: Visualize the stored groove pattern currently in the buffer.
    *   **LIVE Mode**: Real-time visualization of the currently selected item's rhythm.
    *   **LP (Loop Preview)**: Visual feedback for the procedural groove generator.
*   **Groove Generator**: Create synthetic grooves using procedural algorithms and sliders to dial in swing, push/pull, and velocity curves.
*   **Groove Library**: Save, load, and organize your groove presets. Supports persistence across sessions.
*   **Safety & Undo**: "Backup State" feature allows you to experiment freely and restore the original timing/pitch of items at any time.
*   **Smart UX**: Auto-locking visualizer after extraction and optimized workflow for fast iteration.

---

## Requirements

*   **REAPER v7.6x** or later.
*   **ReaImGui**: "ReaScript binding for Dear ImGui" installed via ReaPack.

---

## Compatibility

*   **Operating Systems**:
    *   **Windows**: Fully tested and supported.
    *   **macOS / Linux**: Designed with cross-platform compatibility (including font fallback), but not personally tested. Feedback is welcome!

---

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
    *   Search for `Floop Groove-A-Thor`.
    *   Right-click > **Install**.
    *   Click **Apply**.

### Method 2: Manual Installation

1.  **Install Prerequisites**:
    *   Follow step 1 from the ReaPack method above to install `ReaImGui`.

2.  **Install the Script**:
    *   Download the script file `floop-groove-a-thor.lua`.
    *   Copy to the REAPER resource path folder (REAPER > Options > Show REAPER resource path > Scripts). 

3.  **Load the Action**:
    *   Open the Actions List (`?` shortcut).
    *   Click **New Action > Load ReaScript...**
    *   Select `floop-groove-a-thor.lua`.

---

## Usage
The workflow is divided into three main phases: extract, organize, apply.

### 1. Groove Extraction
Analyze and capture the rhythmic feel from your tracks.
*   **Source Selection**: Select an audio item (drums/percussion) or MIDI item.
*   **Extract**: Click **Extract from Sel**. On success, visualizer switches to **LOCKED** mode automatically.
*   **Length Guard**: Extraction is limited to short loops (max 30 seconds) to ensure performance.
*   **Transient Detection**: The script automatically detects transients (Audio) or note starts (MIDI).
*   **Groove Pool**: The extracted pattern is saved to the groove pool.

### 2. Groove Pool & Banks
Organize your collected grooves.
*   **Groove List**: Click a groove to select it (highlighted in blue).
*   **Banks (Folders)**: Organize grooves into banks using the dropdown menu above the list.
*   **Create Bank**: Click the **+** button to create a new bank.
*   **Navigation**: Use `[..] (Up)` to go back to the root folder, or click a bank name to enter it.
*   **Context Menu**: Right-click a groove to **Rename**, **Delete**, or **Move** to another Bank.
*   **Persistence**: Grooves are saved as `.gat` files in the script directory. Use **Save to Disk** to persist your current groove.

### 3. Groove Application
Apply the extracted groove to target items to impart the "feel".
*   **Target Selection**: Select the target items you want to quantize (Audio or MIDI).
*   **Grid**: Sets the reference grid for quantization and filtering.
*   **Strength**: Controls how strongly the timing matches the groove (0% to 100%).
*   **Velocity (Vel)**: Scales the velocity of MIDI notes to match the groove dynamics.
*   **Quantize**: Pre-quantizes items to the selected Grid before applying groove offset.
*   **Match Window**: Sets the maximum time distance (in ms) to link source notes to grid/groove points.
*   **Target Filter**: Apply groove only to notes near specific grid lines (e.g., 1/4 for kicks only).
*   **Shape (Audio)**: Choose the transient preservation shape (e.g., Hard, Soft) for audio processing.
*   **Apply**: Click **Apply Groove** to process all selected target items. This action is undoable.

### 4. Visualizer
Real-time feedback on your groove and selection.
*   **Modes**:
    *   **LIVE (Selection)**: Shows the waveform/notes of the currently selected item.
    *   **LOCKED (Groove)**: Shows the stored pattern of the selected groove from the pool.
*   **LP Override**: When **LP** is enabled, visualizer shows synthetic generator preview.
*   **Navigation**: `Wheel` = Zoom, `Shift+Wheel` = Scroll.
*   **Feedback**: Green lines = Transients/Notes. Yellow lines = Active Groove Pattern.

### 5. Groove Generator
Create synthetic swing patterns from scratch without needing a source file.
*   **Synthetic Grooves**: Create perfect swing patterns without audio analysis.
*   **Grid**: Select the base resolution (e.g., 1/16).
*   **Swing**: Adjust the swing amount (50% = straight, 66% = triplet feel).
*   **Shortcuts**: Right-click the Swing slider to reset to default (57%).
*   **LP**: Real-time preview of synthetic swing. It is independent from the selected groove.
*   **Generate**: Adds the generated pattern to the Groove Pool.

### 6. Management & Advanced
*   **Rename**: Double-click a groove name or use the context menu.
*   **Multi-Select**: `Ctrl+Click` (Cmd+Click) to select multiple grooves for deletion.
*   **Reset Cache**: Force re-analysis if you manually edited stretch markers or item bounds.

---

## ⚠️ Limitations & Expectations

Groove-A-Thor is a powerful tool for transferring rhythmic feel, but it operates on algorithmic analysis rather than human perception. Please keep the following in mind:

*   **Audio Extraction**: Transient detection relies on clear, defined peaks (like drums or percussion). Complex, polyphonic, or heavily washed-out audio (e.g., full mixes, pads) will not yield clean groove patterns.
*   **Extreme Quantization**: Applying 100% strength with very tight Match Windows on highly unquantized live performances might result in unnatural "stuttering" or skipped notes if the grid and the performance are too far apart.
*   **Best Practice**: Always listen critically. Groove transfer is as much an art as it is a science. Use the `Strength` slider to blend the extracted feel with the original timing, rather than forcing a rigid 100% match.

---

## Changelog

### v1.1.0
* Added: Push/Pull slider to the Procedural Generator to offset the groove ahead/behind the beat.
* Added: Velocity Curve slider to the Procedural Generator to add hierarchical musical dynamics.
* Added: Phase Coherent Mode in the Injector for multi-track drum timing preservation.
* Added: Post-transient RMS detection (15ms lookahead) for accurate Audio Velocity extraction.
* Added: Large offset sanity check warning when extracting audio misaligned with the Base Grid.
* Improved: Visualizer extraction preview now fully syncs with real-time UI threshold/sensitivity adjustments.
* Bugfix: Fixed audio loop start/end marker shifting when applying groove, ensuring loop boundary stability.
* Bugfix: Banks can now be deleted via right-click context menu.

### v1.0.1
* Bugfix: Fixed an issue where applying a groove to an audio item would inadvertently shift the start and end boundaries of the loop. Loop edges are now properly pinned and preserved.

### v1.0.0
* Initial Release.
---

## Support Development

If you find my scripts useful and want to support their development, you can buy me a coffee on Ko-fi:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)

---

## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)

---

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See `LICENSE.txt` in the repository for details.
