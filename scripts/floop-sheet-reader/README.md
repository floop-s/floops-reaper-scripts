# Sheet Reader v2.2.1 - PDF & Image Viewer

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-2.2.1-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)

**Sheet Reader** is a Reaper script that allows you to load and view PDF and image files directly inside Reaper. The script utilizes Poppler to convert PDF files into images for display in the GUI. Users can zoom in and out using the buttons or "Ctrl + Mouse Wheel".

## ⚠️ WINDOWS ONLY

![Platform](https://img.shields.io/badge/Supported-Windows-yellow) ![Platform](https://img.shields.io/badge/macOS%20%2F%20Linux-Unsupported-red)

**This script is developed exclusively for Windows.**
It relies on PowerShell and Windows Script Host for dependency management and process handling. It will **not** function on macOS or Linux.

## Screenshot

<p align="center"> 
  <br> 
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-sheet-reader-s1-v2.1.0.png" target="_blank"> 
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-sheet-reader-s1-v2.1.0.png" width="450" style="border: 1px solid #e5ef2aff;" alt="click to zoom in"> 
  </a> 
  <br> 
</p>

## Key Features

- **Load and view PDF files**: Automatic conversion of PDF pages into images using Poppler.
- **Load and view image files**: Supports PNG, JPG, JPEG.
- **Zoom functionality**: Buttons or "Ctrl + Mouse Wheel".
- **Navigation**: Next/Previous page buttons and keyboard shortcuts (M/N).
- **Direct Page Access**: Type the page number you want to view.
- **Cache Management**: Efficient caching of converted PDF pages.

## Requirements

- **REAPER** 7.5x or later
- **ReaImGui**: "ReaScript binding for Dear ImGui" installed via ReaPack.
- **SWS/S&M Extension**
- **Windows** (PowerShell and Windows Script Host available)
- **Internet access** (optional, for automatic Poppler download)

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
    *   Search for `Floop Sheet Reader`.
    *   Right-click > **Install**.
    *   Click **Apply**.

### Method 2: Manual Installation   

1.  **Dependencies**: Install SWS/S&M Extension and ReaImGui via ReaPack.
2.  **Install Script**: Place `Floop Sheet Reader.lua` in your REAPER Scripts folder.
3.  **Poppler**:
    - When first run, the script checks for `pdftoppm`.
    - If missing, it prompts to auto-download and install Poppler to Reaper's resource folder.
    - Manual install: Download [Poppler for Windows](https://github.com/oschwartz10612/poppler-windows/releases) and place in Reaper resources.

## Usage

1.  Run the script from the Action List.
2.  Load a PDF or image file via the UI buttons.
3.  **Navigate**:
    - `+` / `-` buttons to zoom.
    - `Ctrl + Mouse Wheel` to zoom quickly.
    - `M` key: Next page.
    - `N` key: Previous page.
4.  **Cache**: Use the Cache Manager to clear cached images if needed.

## Troubleshooting

- **Download Issues**: Ensure internet connectivity and write permissions.
- **Conversion Issues**: Check `pdftoppm.err.txt` in `pdf_images/` subfolders.
- **Images**: Ensure texture size is valid.
- **Environment**: Antivirus/Firewall may need exceptions for the REAPER resource path.

## Changelog

### Version 2.2.1 (2026-07-02)
- **Maintenance**: Updated Poppler Windows binary download link and SHA256 verification hash.

### Version 2.2.0 (2026-04-06)
- **Performance**: Completely resolved UI freezing during Poppler installation using an asynchronous VBS/PowerShell pipeline.
- **Stability**: Re-written image caching system to fix memory leaks and prevent "invalid texture" errors caused by garbage collection.
- **UX**: "Select PDF/Image" now correctly remembers the last accessed directory across sessions.
- **Security**: Scoped all global functions to local for script safety and better performance.
- **UI**: Polished About/Credits modal.

### Version 2.1.0 (2026-01-07)
- **About / Credits**: Added '?' button with Poppler attribution and GitHub link.
- **UI**: Restored 'Clear Cache' button to main UI for faster access.
- **Fixes**: Corrected tooltip contrast for better readability.

### Version 2.0 (2025-12-08)
- **Cache Manager**: Always available, with columns for status and safe deletion.
- **Optimization**: Fast cache path skips external commands when complete.
- **Stability**: Sanitized folder names, robust path handling, texture validation.
- **Poppler**: Integrity check (SHA256), download progress, targeted abort.
- **UI**: Improved legibility, progress feedback, error messages.
- **Navigation**: Updated shortcuts (M/N).

### Version 1.0 (2025-03-09)
- Initial release.


## Credits

- **Poppler**: PDF rendering library by Derek Schuff (https://poppler.freedesktop.org/).
- **Windows Binaries**: Sourced from oschwartz10612/poppler-windows (https://github.com/oschwartz10612/poppler-windows).

## Support

All my tools are free and open-source.
If they help your workflow, consider supporting the project on Ko-fi

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)

## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See the `LICENSE.txt` file in the main repository for details.
