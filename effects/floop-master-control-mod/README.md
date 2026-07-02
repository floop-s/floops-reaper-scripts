# Floop Master Control (Modular)

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-1.1.0-green) ![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)

Modular master monitoring and analysis suite for REAPER (JSFX).

## Overview

Floop Master Control (Modular) is a rewrite of the original Floop Master Control, designed around a slot-based modular UI.

You get up to 9 independent UI slots (default layout is 6 slots). Each slot can host one analysis/monitoring module, and you can swap modules without adding multiple FX instances.

## Overview & Media


<p align="center">
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-def.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-def.png" height="210" style="border: 1px solid #27a086ff;" alt="Default layout">
  </a>
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-empty.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-empty.png" height="210" style="border: 1px solid #27a086ff;" alt="Empty layout">
  </a>
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-custom-menu.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-custom-menu.png" height="210" style="border: 1px solid #27a086ff;" alt="Custom menu">
  </a>
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-embedded.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-embedded.png" height="210" style="border: 1px solid #27a086ff;" alt="Embedded">
  </a>
</p>

## Modules

- True Peak & LUFS Meter (TP + LUFS-S + LUFS-I)
- Spectrum Analyzer (Mid/Side, temporal averaging, smoothing, hold/freeze)
- Phase Correlation
- Multi-band Phase
- Stereo Analyzer (Goniometer)
- Oscilloscope
- Spectrogram
- Monitor Control (Dim, Solo Mid/Side, Low/Mid/High focus)
- VU Meter

## Requirements

- REAPER v7.5x or later.
- Compatible with other DAWs via YSFX (VST/AU wrapper for JSFX).

## Installation

### ReaPack

1. Open Extensions > ReaPack > Import Repositories...
2. Add:
   https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
3. Open Extensions > ReaPack > Browse Packages
4. Search for Floop Master Control (Modular) and install.
5. Click Apply.

### Manual Installation

1. Open REAPER.
2. Go to Options > Show REAPER resource path...
3. Enter the Effects folder.
4. Copy the entire folder:
   floop-master-control-mod
5. Restart REAPER (recommended) or press F5 in the FX Browser.
6. In the FX Browser, search for Floop Master Control (Modular).

## Usage

### Slot workflow

- Each slot has a + button that opens the module picker for that slot.
- Use + ADD MODULE at the bottom to populate the first empty slot.
- The UI starts with 6 slots by default; add more slots as needed up to 9.
- Slot selection is instant; modules are pre-initialized to avoid dynamic loading complexity.

### Global controls

- Config (C): toggles parameter sliders (click to view the native parameter list for MIDI learning).
- Most analysis settings (limits, smoothing, modes) are global to the instance and apply to all slots using that module.

### MIDI/Automation mapping

All module parameters (such as True Peak Limits, Dim levels, Monitor crossover frequencies, and Monitor modes including Band Focus Low/Mid/High) are exposed as native REAPER sliders. You can map them to external hardware controllers using REAPER's standard "MIDI Learn" or use them in track envelopes for automation.

### Module interactions

- True Peak & LUFS Meter
  - Click MAX to reset true peak maximum.
  - Click LUFS-S or INT to reset loudness history.
  - When transport is stopped: TP shows -inf, LUFS-S shows --.- (meter-grade idle behavior).
- Spectrum Analyzer
  - ST / M/S: stereo vs mid/side display mode.
  - ms slider: temporal averaging time (up to 5000 ms).
  - 1/3..1/24: smoothing control (drag), right-click cycles presets.
  - H: Left-click to hold peaks, Right-click to toggle the peak line visibility.
  - F: freeze display.
  - Mouse wheel (over the left axis or graph): adjust the floor offset (view shift), right-click to reset.
  - Control tooltips: hover buttons/sliders to see what each control does.
  - Hover: frequency + level tooltip (including floor offset 'V').
- Oscilloscope
  - L/R: toggle channels.
  - Mouse wheel: zoom time scale.
- Spectrogram
  - Mouse wheel (over the module): adjust speed.
  - Resizing preserves the image history (no blank frame on resize).
- VU Meter
  - Mouse wheel: adjust Rise Time (RT).
  - Left-click + drag vertically: adjust Overshoot (OS).
  - Right-click: reset RT and OS to default values.
  - Settings are shown  on hover.
- Monitor Control
  - NORMAL / SOLO MID / SOLO SIDE
  - DIM (set from the Config sliders)
  - LOW / MID / HIGH focus and their combinations (two crossover frequency sliders)
- Multi-band Phase
  - Log-frequency display with octave smoothing; stabilized at very low energy to avoid misleading readings.

## Compatibility

Floop Master Control (Modular) is derived from the original Floop Master Control, but the two plugins are kept as separate effects to avoid project conflicts.

- Floop Master Control (original): kept for compatibility and may receive occasional maintenance updates.
- Floop Master Control (Modular): the actively developed version.

## Performance notes

- CPU use scales with the number of active slots and the chosen modules.
- FFT-based modules (Spectrum Analyzer, Spectrogram, Multi-band Phase, Stereo Analyzer) typically cost more than simple meters/controls.

## Changelog

### v1.1.0

- **Monitor Module**: Added support for arbitrary multi-band selections (e.g., LOW + HIGH) via perfectly flat Linkwitz-Riley 4th order (LR4) additive routing.
- **Fix**: Added 1-pole lowpass smoothing to monitor gain to prevent audio clicks when toggling DIM.

### v1.0.0

- Initial release of the modular rewrite (slot-based architecture).

## Support Development

If you find my scripts useful and want to support their development, you can buy me a coffee on Ko-fi:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)

## Author

Developed by Flora Tarantino  
Project home: https://www.floratarantino.com/floop-reaper-scripts/

## Credits

Inspired by A. Lunedì's master workflow

## License

Licensed under the GNU General Public License v3.0 (GPL-3.0).  
See the main repository for details.
