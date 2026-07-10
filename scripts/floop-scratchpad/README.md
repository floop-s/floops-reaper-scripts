# Floop Scratchpad

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-2.1.2-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)

**Track Notes System for REAPER.**


## Overview

**Floop Scratchpad** is a REAPER script that lets you write, view, and manage notes per track directly in your DAW.
With the massive **V2.0 update**, all notes are saved natively inside your `.rpp` project file using `ProjExtState`, completely eliminating the need for external text files or background startup scripts.
The script generates a companion JSFX (FloopNoteReader) that displays your notes in the Track/Mixer panels when embedding is enabled, complete with custom background colors and native word-wrapping.

## Screenshots
<p align="center"> 
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-scratchpad-v2.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-scratchpad-v2.png" width="700" style="border: 1px solid #27a086ff;" alt="Floop Hunter Framework Action">
  </a>
</p>

<p align="center">
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-scratchpad-v2-original theme.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-scratchpad-v2-original theme.png" width="48%" style="border: 1px solid #27a086ff; margin-right: 1%;" alt="Floop Scrtachpad V2 Original Theme">
  </a>
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-scratchpad-v2-dynamic-theme.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-scratchpad-v2-dynamic-theme.png" width="48%" style="border: 1px solid #27a086ff;" alt="Floop Scrtachpad V2 Dynamic Theme">
  </a>
</p>



## Key Features (V2)

*   **Native Project Saving**: Notes are stored directly inside your `.rpp` file. No external `.txt` files to manage or lose.
*   **Dynamic UI Theme**: Toggle "UI Theme" to instantly match Floop Scratchpad's colors with your current REAPER theme.
*   **JSFX Background Color Picker**: Choose a custom background color for the JSFX reader on a per-track basis.
*   **Native Word-Wrapping**: The JSFX reader now dynamically wraps text to fit your Track Control Panel width.
*   **High-DPI / Retina Ready**: Crisp, clear fonts on 4K and Mac Retina displays.
*   **Migrate V1**: One-click button to safely import your old external text notes into the new V2 format.
*   **Zero Background Overhead**: The old startup background script is **no longer needed** and can be safely removed from your SWS actions.

## Requirements

*   **REAPER v7.5x** or later.
*   **ReaImGui**: "ReaScript binding for Dear ImGui" installed via ReaPack. **Minimum version required: 0.10.2+**.

## Compatibility

*   **REAPER**: Developed and tested on **v7.5x+**.
*   **Operating Systems**: Windows, macOS, and Linux (Fully Cross-Platform).

## Installation

The easiest way to install and keep the script updated is via **ReaPack**.

### Method 1: ReaPack (Recommended)

1.  **Install Prerequisites**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for and install: `ReaScript binding for Dear ImGui`
    *   **Restart REAPER**.

2.  **Add the Repository**:
    *   Open **Extensions > ReaPack > Import Repositories...**
    *   Copy and paste this URL:
        https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
    *   Click **OK**.

3.  **Install the Script**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for `Floop Scratchpad`.
    *   Right-click > **Install**.
    *   Click **Apply**.

*(Note: If you are updating from V1, you can safely remove `Floop Startup Refresh.lua` from your SWS Project Startup Actions. It is no longer required!)*

## Usage

1.  **Launch** "Floop Scratchpad" from the Actions List.
2.  **Select a track**: Its name and GUID appear in the interface.
3.  **Type notes** and adjust Text Size or Background Color.
4.  **Save**: Notes auto-save when switching tracks. You can also press **Ctrl+S** / **Cmd+S** to save instantly, or **Ctrl+Enter** / **Cmd+Enter** to save and close the window immediately. Pressing **ESC** will close the window safely (auto-saving if needed).

### Embedding Notes in TCP / MCP

   *   Click "+ Add JSFX" in the script UI.
   *   In the FX Browser, find `FloopNoteReader`.
   *   Right-click > "Default settings for new instance" > Enable "Show embedded UI in TCP or MCP".
   *   Future instances will automatically embed themselves in the track panel!

## Changelog

### v2.1.2
* **UX/Performance Improved:** Advanced dynamic theme engine fixes the light-theme bug on modern REAPER defaults and drastically reduces CPU usage.

### v2.1.1
* **UX Improved:** Remembers the last used Text Size when switching to tracks without saved state.

### v2.1.0
* **UX Improved:** Added workflow shortcuts to speed up saving/closing (`Ctrl/Cmd+S`, `Ctrl/Cmd+Enter`, `ESC`).
* **JSFX Update:** Text color adapts (light/dark) based on background color for readability.
* **Color Picker:** Added saved color palette (5 slots).

### v2.0.1 (Hotfix)
* **UI Hotfix:** Adjusted text wrapping layout inside the Help Guide modal.

### v2.0.0
*   **Major Architecture Rewrite**: Notes are now saved natively in the REAPER project file (`.rpp`) via `ProjExtState`.
*   **Removed**: `Floop Startup Refresh.lua` is obsolete. The script now handles offline sync instantly upon opening the UI.
*   **Added**: JSFX Background Color Picker (saved per-track).
*   **Added**: Dynamic UI Theme toggle to match REAPER's native colors.
*   **Added**: "Migrate V1" button to easily import legacy `.txt` files into the new native format.
*   **Added**: Native EEL2 word-wrapping engine in the JSFX. Text now dynamically flows and resizes when shrinking the TCP.
*   **Added**: High-DPI / Retina display support for the JSFX graphics.
*   **Added**: `Ctrl+S` / `Cmd+S` keyboard shortcut for instant saving.
*   **Fixed**: Critical track duplication bug where copied tracks shared the same JSFX memory buffer.
*   **Fixed**: JSFX file I/O overhead on Windows that caused continuous disk writing.
*   **Improved**: Complete UI overhaul with constrained window scaling, adaptive modals, and cleaner layouts.

### v1.3.0 (Legacy)
*   **Added**: Global Memory (gmem) architecture for JSFX readers, vastly improving performance and reducing disk I/O.
*   **Fixed**: Resolved a bug where all JSFX instances shared the same text across different tracks.
*   **Fixed**: Background startup script now automatically restores volatile gmem notes on project load.
*   **Note**: Notes written in unsaved projects cannot currently be migrated to saved projects. Please save your project before adding notes.

### v1.2.4 (2026-02-17)
*   **Added**: Numeric JSFX font size input next to the Font Scale slider (14–40 px).
*   **Improved**: Increased JSFX font size range and clamping for large sessions and high-DPI layouts.
*   **Fixed**: JSFX Note Reader now updates immediately when confirming font size changes from the numeric input.

### v1.2.3 (2026-01-08)
*   **Fixed**: Critical issue where notes were lost when saving a previously unsaved project (implemented proactive in-memory migration).
*   **Fixed**: JSFX reader disappearing when adjusting font scale on tracks with empty notes.
*   **Fixed**: Race condition when switching project tabs.
*   **Improved**: Added numeric value display next to the Font Scale slider.
*   **Internal**: Improved project path detection using project pointers.

### v1.2.2 (2026-01-06)
*   **Fixed**: Linux compatibility issue (`attempt to concatenate a nil value`) by replacing Windows-specific environment variables with cross-platform path helpers.
*   **Fixed**: Function scope error in `Floop Startup Refresh.lua` that could cause runtime failures.
*   **Fixed**: Issue where notes disappeared when adjusting font scale slider (added auto-save and error checking before refresh).
*   **Fixed**: Note migration logic (removed filter) to ensure all notes are preserved when saving a temporary project.
*   **Improved**: Path handling and directory separators for all operating systems (Windows, macOS, Linux).

### v1.2.1 (2025-12-29)
*   **Added**: Mac/Linux support via `getSystemHome()` to resolve user home directory.
*   **Improved**: Path construction now uses `joinPath` for cross-platform compatibility.
*   **Updated**: `Floop Startup Refresh.lua` aligned with path and OS compatibility fixes.

### v1.1.0 (2025-10-23)
*   **Added**: SWS/S&M Project Startup Action integrating `Floop Startup Refresh.lua` to refresh JSFX on project open.
*   **Added**: Per-track font size persistence (`FontScale:` saved per GUID) and restored on load.
*   **Changed**: Autosave on track change now persists font size alongside notes.
*   **Fixed**: Startup refresh regenerates JSFX only for tracks with non-empty notes, using saved font scale.
*   **Note**: Requirements updated — SWS/S&M needed for automatic project startup refresh.

### v1.0.1 (2025-10-16)
*   **Fixed**: Clear Note File re-added JSFX on all tracks; refresh now re-adds only on tracks with non-empty notes.
*   **Changed**: Saving an empty note removes the JSFX; saving non-empty notes re-adds/updates the JSFX.

### v1.0.0 (2025-10-14)
*   Initial release.
*   **Added**: Auto-generated JSFX Note Reader per track.
*   **Added**: Prevention of duplicate JSFX instances on the same track.
*   **Fixed**: Slider flicker removed by refreshing after edit ends.

## Support Development

If you find my scripts useful and want to support their development, you can buy me a coffee on Ko-fi:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)

## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See the `LICENSE.txt` file in the main repository for details.
