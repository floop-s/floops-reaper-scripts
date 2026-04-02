# Floop’s REAPER Scripts

This repository contains a collection of **JSFX effects** and **Lua scripts** for
**REAPER**, focused on audio processing, monitoring, and workflow enhancement.

All tools are released as **free and open-source software**.

---

## Repository Structure

The tools are organized into the following directories:
- `scripts/`: Lua scripts
- `effects/`: JSFX effects

Each tool is contained in its own folder and typically includes:
- the script or effect file (`.lua` or `.jsfx`)
- a dedicated `README.md` with usage instructions and details

This structure allows the repository to be used both:
- via **ReaPack**
- and by manually downloading individual tools from GitHub

---

## Installation

### Automatic Installation (Recommended – ReaPack)

1. Open **REAPER**
2. Go to **Extensions → ReaPack → Import Repositories…**
3. Paste the following URL:

`https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml`

4. The repository will appear in ReaPack.
Browse and install scripts or effects as needed.

---

### Manual Installation

1. Download the repository
- Clone it with Git or download it as a ZIP file.

2. Locate the REAPER resource path
- In REAPER, go to
  **Options → Show REAPER resource path in explorer / finder**

3. Install the files
- **Lua scripts**:
  Copy `.lua` files into the `Scripts` folder.
- **JSFX effects**:
  Copy `.jsfx` files into the `Effects` folder.

4. Refresh REAPER
- **Lua scripts**:
  Open the **Actions List** (`?`) →
  **New Action → Load ReaScript…**
- **JSFX effects**:
  Open the FX Browser and press **F5** to rescan effects.

Refer to each tool’s own `README.md` for specific usage instructions and requirements.

---

## Compatibility

- **Primary platform:**
Developed and tested on **Windows**.

- **macOS / Linux:**
Some scripts are designed to be cross-platform, but not all tools are tested on these systems. Compatibility and stability are not guaranteed.
Feedback is welcome.

---

## Support & Expectations

All scripts and effects are provided **as-is**.

- No guaranteed support is provided.
- Bug reports and feedback are welcome, but responses may be limited.
- Tools are tested only on systems I have direct access to.

This project is maintained in my spare time.

If these tools save you time, a coffee is always appreciated. ☕

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)

---





## License

All contents of this repository are released under the
**GNU General Public License v3.0 (GPL-3.0)**.

See the `LICENSE` file for full license details.
