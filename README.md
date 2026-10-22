<div align="center">

# Floop's REAPER Scripts

**Free, open-source Lua scripts and JSFX plugins for REAPER**

Modular master metering · vocal cleanup (de-esser, de-plosive, breath remover) · groove extraction · live looping · track notes · saturation · compression · transient shaping

<br>

[![Website](https://img.shields.io/badge/Website-floop--reaper--scripts-0a7cff?style=for-the-badge&logo=googlechrome&logoColor=white)](https://floratarantino.com/floop-reaper-scripts)
[![Install with ReaPack](https://img.shields.io/badge/Install-ReaPack-7b42bc?style=for-the-badge)](#installation)

[![GitHub stars](https://img.shields.io/github/stars/floop-s/floops-reaper-scripts?style=flat-square&logo=github)](https://github.com/floop-s/floops-reaper-scripts/stargazers)
[![Last commit](https://img.shields.io/github/last-commit/floop-s/floops-reaper-scripts?style=flat-square)](https://github.com/floop-s/floops-reaper-scripts/commits/main)
[![Release downloads](https://img.shields.io/github/downloads/floop-s/floops-reaper-scripts/total?style=flat-square&label=release%20downloads)](https://github.com/floop-s/floops-reaper-scripts/releases)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue?style=flat-square)](LICENSE)
![REAPER](https://img.shields.io/badge/REAPER-Lua%20%7C%20JSFX-555?style=flat-square)
![Platform](https://img.shields.io/badge/Windows-tested-success?style=flat-square&logo=windows)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?style=flat-square&logo=ko-fi&logoColor=white)](https://ko-fi.com/floopsreaperscripts)

</div>

> **Install everything in 30 seconds with ReaPack** — add this URL in *Extensions → ReaPack → Import repositories*:
> ```
> https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
> ```

---

## ⭐ Featured: Floop Master Control (Modular)

**One JSFX, up to 9 slots, any combination of analysis modules** — peak/LUFS meter, VU, spectrum, spectrogram, phase scope, correlation, stereo field, oscilloscope and monitoring. Swap modules per slot without stacking multiple FX instances. No dependencies: drop it on your master and go.

<p align="center">
  <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-def.png" height="460" alt="Floop Master Control Modular – modular metering suite for REAPER">
  &nbsp;
  <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-custom-menu.png" height="460" alt="Master Control Modular – module selection menu">
  &nbsp;
  <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-embedded.png" height="460" alt="Master Control Modular – embedded in the mixer">
</p>

**[→ Full documentation](effects/floop-master-control-mod)**

---

## Contents

- [Vocal & dialogue editing](#vocal--dialogue-editing)
- [Workflow & productivity](#workflow--productivity)
- [Music & performance](#music--performance)
- [Audio effects (JSFX)](#audio-effects-jsfx)
- [Installation](#installation)
- [Feedback & bug reports](#feedback--bug-reports)

---

## At a glance

| Tool | Type | What it does | Requires |
|---|---|---|---|
| [Hunter Framework](scripts/floop-hunter-framework) | Lua | Detects sibilance, plosives and breaths, writes volume automation | ReaImGui, SWS |
| [Ess Hunter](scripts/floop-ess-hunter) | Lua | Automatic de-essing via volume automation | ReaImGui, SWS |
| [Scratchpad](scripts/floop-scratchpad) | Lua | Notes per track, saved inside the project | ReaImGui 0.10.2+ |
| [Search](scripts/floop-search) | Lua | Keyboard-first track search and navigation | ReaImGui 0.10.2+, SWS |
| [Sheet Reader](scripts/floop-sheet-reader) | Lua | View PDFs and images inside REAPER | ReaImGui, SWS · **Windows only** |
| [Bill The Pain Clock](scripts/floop-bill-the-pain-clock) | Lua | Background time tracking per project, for billing | ReaImGui 0.10.2+ |
| [Key & BPM Sniffer](scripts/floop-key-bpm-sniffer) | Lua | Detects key and tempo of audio items | ReaImGui |
| [Time-Based FX Calculator](scripts/floop-useless-time-based-effects-calculator) | Lua | Delay / reverb / release times from BPM | ReaImGui 0.10.2+ |
| [Groove-A-Thor](scripts/floop-groove-a-thor) | Lua | Extract, generate and apply groove (audio ↔ MIDI) | ReaImGui |
| [Floopa Station](scripts/floopa-station) | Lua | 5-track live looper with count-in and auto-loop | ReaImGui 0.10.2+, SWS |
| [Studio Trainer](scripts/floop-studio-trainer) | Lua | Practice loops with automatic BPM increase | ReaImGui 0.10.2+ |
| [Chrominator](effects/floop-chrominator) | JSFX | Stereo analog-style saturator, 5 modes | — |
| [Multiband Transient Shaper](effects/floop-multiband-transient-shaper) | JSFX | 3-band attack/sustain, up to 8× oversampling | — |
| [Vert-ish VCA Compressor](effects/floop-vert-ish) | JSFX | VCA bus compressor with L/R controls | — |
| [Master Control (Modular)](effects/floop-master-control-mod) | JSFX | Slot-based metering: LUFS, spectrum, phase, scope… | — |
| [Master Control](effects/floop-master-control) | JSFX | All-in-one master metering and true peak | — |

---

## Vocal & dialogue editing

### [Floop Hunter Framework](scripts/floop-hunter-framework)
Automatic vocal cleanup: finds **sibilance, plosives and breaths** and writes precise volume automation only where needed no plugin, no tone change, fully editable afterwards. Overlapping detections are merged cleanly.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-hunter-framework-ess.png" width="640" alt="Floop Hunter Framework – sibilance detection in REAPER"></p>

### [Floop Ess Hunter](scripts/floop-ess-hunter)
The standalone de-esser version of the Hunter: detects "s", "sh", "ch" and lowers them with envelope points.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-ess-hunter-interface.png" width="640" alt="Floop Ess Hunter – automatic de-esser for REAPER"></p>

---

## Workflow & productivity

### [Floop Scratchpad](scripts/floop-scratchpad)
Write notes per track, stored inside the `.rpp` file. Optional embedded display in the TCP / mixer.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-scratchpad-v2.png" width="640" alt="Floop Scratchpad – track notes in REAPER"></p>

### [Floop Search](scripts/floop-search)
A floating search bar to find, select and preview any track by name or number, without the mouse.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-search-v1.0.0-s1.png" width="640" alt="Floop Search – track search bar for REAPER"></p>

### [Floop Sheet Reader](scripts/floop-sheet-reader) · *Windows only*
Open PDFs and images (sheet music, lyrics, notes) in a dockable REAPER window.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-sheet-reader-s1-v2.1.0.png" width="640" alt="Floop Sheet Reader – PDF viewer inside REAPER"></p>

### [Floop Bill The Pain Clock](scripts/floop-bill-the-pain-clock)
Tracks the time spent on each project in the background, with idle detection — made for billing clients.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-bill-the-pain-clock.png" width="640" alt="Floop Bill The Pain Clock – REAPER time tracker"></p>

### [Floop Key & BPM Sniffer](scripts/floop-key-bpm-sniffer)
Detects musical key and tempo of selected audio items.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-key-bpm-sniffer-big.png" width="640" alt="Floop Key and BPM Sniffer – key and tempo detection"></p>

### [Floop Time-Based Effects Calculator](scripts/floop-useless-time-based-effects-calculator)
Delay times, reverb pre-delay/decay and compressor release synced to project BPM.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-useless-time-calculator-v1.1.0.png" width="640" alt="Time-based effects calculator for REAPER"></p>

---

## Music & performance

### [Floop Groove-A-Thor](scripts/floop-groove-a-thor)
Extract timing and velocity feel from audio or MIDI, apply it elsewhere, or generate new grooves.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-groove-a-thor.png" width="640" alt="Floop Groove-A-Thor – groove extraction for REAPER"></p>

### [Floopa Station](scripts/floopa-station)
Live looper with 5 dedicated tracks, count-in, beat counter, auto-loop and micro-fades.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floopa-station-v1.1.0.png" width="640" alt="Floopa Station – live looper for REAPER"></p>

### [Floop Studio Trainer](scripts/floop-studio-trainer)
Loop a section or the metronome; the BPM rises automatically after each set of repetitions.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-studio-trainer-v1.1.png" width="640" alt="Floop Studio Trainer – practice tool with adaptive BPM"></p>

---

## Audio effects (JSFX)

### [Floop Chrominator](effects/floop-chrominator)
Stereo analog-style saturation with five modes (Soft, Even, Clip, Warm, Odd).

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-chrominator-2.png" width="640" alt="Floop Chrominator – JSFX saturator"></p>

### [Floop Multiband Transient Shaper](effects/floop-multiband-transient-shaper)
Independent attack, sustain and gain on three bands, up to 8× oversampling.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-multiband-transient-shaper-interface.png" width="640" alt="Multiband transient shaper JSFX for REAPER"></p>

### [Vert-ish VCA Compressor](effects/floop-vert-ish)
VCA-style compressor for bus glue and drums, dual-mono or linked, with saturation and oversampling.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-vert-ish-v1.0.0.png" width="640" alt="Vert-ish VCA compressor JSFX"></p>

### [Floop Master Control (Modular)](effects/floop-master-control-mod)
Up to 9 slots, each hosting a module: meter, VU, spectrum, spectrogram, phase, correlation, stereo, oscilloscope, monitor.

<p align="center"><img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-master-control-modular-def.png" height="460" alt="Floop Master Control Modular – metering suite for REAPER"></p>

### [Floop Master Control](effects/floop-master-control)
The original all-in-one version: true peak, LUFS, spectrum and phase in one plugin.

---

## Installation

### ReaPack (recommended — includes automatic updates)
1. Install [ReaPack](https://reapack.com) if you don't have it.
2. *Extensions → ReaPack → Import repositories…* and paste:
   ```
   https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
   ```
3. *Extensions → ReaPack → Browse packages*, search **floop**, install what you need.

Most scripts need **ReaImGui** (install *"ReaScript binding for Dear ImGui"* from ReaPack) and some need the [SWS Extension](https://www.sws-extension.org). See the table above.

### Manual / single download
Every tool also has a downloadable **[Release](https://github.com/floop-s/floops-reaper-scripts/releases)**.
1. *Options → Show REAPER resource path*
2. Copy `.lua` files into `Scripts/`, `.jsfx` files into `Effects/`
3. Load scripts from the Actions list; press F5 in the FX browser for JSFX.

---

## Compatibility
- **Windows**: primary platform, fully tested.
- **macOS / Linux**: most tools should work (pure Lua + ReaImGui / JSFX) but are not fully tested. Reports are very welcome.

---

## Feedback & bug reports

ReaPack doesn't tell me who uses what — **your feedback is the only signal I get.**

- 🐛 Found a bug? [Open an issue](https://github.com/floop-s/floops-reaper-scripts/issues/new) — include REAPER version, OS and tool version.
- 💡 Idea or question? Use [Discussions](https://github.com/floop-s/floops-reaper-scripts/discussions).
- ⭐ If a tool saves you time, a **star** on this repo helps other REAPER users find it.

The project is maintained in my spare time. If you'd like to support it: [Ko-fi](https://ko-fi.com/floopsreaperscripts).

---

## License
GPLv3 — see [LICENSE](LICENSE).
