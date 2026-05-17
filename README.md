# Floop’s REAPER Scripts

This repository contains JSFX effects and Lua scripts for REAPER.

The tools focus on workflow enhancement, audio processing, and music production utilities.

All content is released as open-source software under the GPLv3 license.

---

## Repository Structure

- `scripts/` - Lua scripts
- `effects/` - JSFX effects

Each tool is contained in its own folder and includes:
- source file (`.lua` or `.jsfx`)
- dedicated README with usage details

The repository can be used via ReaPack or manual installation.

---

## Installation

### ReaPack (recommended)

1. Open REAPER
2. Go to Extensions → ReaPack → Import Repositories
3. Add:

```
https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
```

4. Install tools from ReaPack browser

---

### Manual installation

1. Download or clone the repository
2. Open REAPER → Options → Show REAPER resource path
3. Copy files into:

- `.lua` → Scripts/
- `.jsfx` → Effects/

4. Refresh REAPER (Actions List for scripts, F5 for JSFX)

---

## Featured Tools

### Workflow & Editing
- Floop Scratchpad - notes attached to tracks
- Floop Sheet Reader - PDFs and images inside REAPER
- Floop Search - track navigation and filtering
- Floop Studio Trainer - instrument practice with adaptive BPM
- Floop ESS Hunter / Hunter Framework - detection and marking system for sibilance, plosives, and breath events for dialogue editing

### Music Tools
- Floop Groove-A-Thor - groove extraction, transfer, and generation
- Floopa Station - live looping tool

### Audio Processing
- Floop Chrominator - stereo saturation
- Floop Master Control (Modular) - modular metering and analysis system

---

## Compatibility

- Primary platform: Windows (tested)
- macOS / Linux: partially supported, not fully tested

---

## Support

The project is maintained in spare time.

Tools are provided as-is. Feedback is welcome but not guaranteed to be addressed.

If useful, support is appreciated:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)

---

## License

GPLv3 - see LICENSE file for details.