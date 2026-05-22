# Floop Search

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-1.1.0-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)
**Track Navigation System for REAPER.**

## Overview

**Floop Search** is a Lua script for REAPER that brings a search bar for rapid track navigation, selection, and previewing.
It features a sleek, floating, animated interface that stays out of your way until you need it.
Designed for speed and keyboard-centric workflows, it allows you to find any track by name or track number without touching the mouse.

## Screenshots

<p align="center"> 
 <br> 
 <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-search-v1.0.0-s1.png" target="_blank"> 
   <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-search-v1.0.0-s1.png" width="450" style="border: 1px solid #202121ff;" alt="Click to zoom in"> 
 </a> 
 <br> 
 </p>
 <p align="center"> 
 <br> 
 <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-search-v1.0.0-s2.png" target="_blank"> 
   <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-search-v1.0.0-s2.png" width="450" style="border: 1px solid #202121ff;" alt="Click to zoom in"> 
 </a> 
 <br> 
 </p>

## Key Features

- **Modern Search UI**: Floating search bar that animates and expands to show results.
- **Fast Search**: Instantly filter tracks by Name or Track Number.
- **Multi-Query Support**: Use a comma (`,`) to search multiple groups at once (e.g. `kick, snare`).
- **Keyboard Navigation**: Full control using Arrow keys, Enter, and Esc.
- **Preview Solo**: Temporarily solo tracks while navigating results to quickly audition content (Hold ALT).
- **State Restoration**: Automatically restores original track selection, solo states, and colors upon exit.
- **Undo Safe**: All track selections are safely grouped into a single Undo block.
- **Visual Feedback**: Matches highlight colors (red) for clear visibility during navigation.
- **Auto-Focus**: Smart window focus handling for immediate typing.

## Requirements

- **REAPER v7.5x** or later.
- **ReaImGui**: "ReaScript binding for Dear ImGui" installed via ReaPack. **Minimum version required: 0.10.2+**.

## Compatibility

- **REAPER**: Developed and tested on **v7.5x+** (Windows).
- **Operating Systems**:
  - **Windows**: Fully tested and supported.
  - **macOS / Linux**: Designed with cross-platform compatibility in mind, but not personally tested on these systems. Feedback is welcome!

## Installation

The easiest way to install and keep the script updated is via **ReaPack**.

### Method 1: ReaPack (Recommended)

1.  **Install Prerequisites**:
    - Open **Extensions > ReaPack > Browse Packages**.
    - Search for and install:
      - `ReaScript binding for Dear ImGui`
      - `SWS/S&M Extension`
    - **Restart REAPER**.

2.  **Add the Repository**:
    - Open **Extensions > ReaPack > Import Repositories...**
    - Copy and paste this URL:
      https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
    - Click **OK**.

3.  **Install the Script**:
    - Open **Extensions > ReaPack > Browse Packages**.
    - Search for `Floop Search`.
    - Right-click > **Install**.
    - Click **Apply**.

### Method 2: Manual Installation

1.  **Install ReaImGui**:
    - Go to **Extensions > ReaPack > Browse Packages**.
    - Search for and install `ReaImGui`.
    - Restart REAPER.
2.  **Install the Script**:
    - Copy `Floop Search.lua` to your REAPER Scripts folder.
3.  **Load the Action**:
    - Open Actions List (`?`).
    - Load `Floop Search.lua`.
    - (Recommended) Assign a **Global + Text** shortcut (e.g., `Ctrl+Space`) to launch/toggle while typing.

## Usage

1.  **Launch** the script.
2.  **Type** to search:
    - Part of a name (e.g., "Voc", "Kick").
    - Track number (e.g., "12").
3.  **Navigate**:
    - **UP / DOWN**: Move through results.
    - **ALT (Hold)**: Preview Solo the highlighted track.
4.  **Confirm**:
    - **ENTER**: Select track, scroll to view, expand parents, and close script.
5.  **Cancel**:
    - **ESC**: Close without changes (restores previous state).

## Troubleshooting

- **"ReaImGui API not found"**: Install ReaImGui via ReaPack.
- **Shortcut not working**: Ensure Scope is "Global + Text".

## Changelog

### v1.1.0 (2026-05-22)

- **Feature**: Added support for the comma operator (`,`) to search for multiple track groups at once (e.g. `kick, snare`).
- **Feature**: Added `SHIFT + ENTER` shortcut to select all tracks found in the search results.
- **Improvement**: Added full Undo block support. Pressing Undo after selecting tracks will safely revert the selection.
- **Improvement**: Introduced 'Lazy Snapshot' engine. The script now loads instantly even on projects with thousands of tracks and perfectly preserves custom user colors.
- **Bugfix**: Hidden tracks (TCP) are now properly ignored by the search engine.

### v1.0.0 (2026-01-06)

- Initial release.
- Basic track search functionality.
- Track selection and previewing.
- Animated floating UI.
- Debounced search for smooth performance.

## Support Development

If you find my scripts useful and want to support their development, you can buy me a coffee on Ko-fi:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)

## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See the `LICENSE.txt` file in the main repository for details.
