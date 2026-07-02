# Floop Bill The Pain Clock

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg) ![Version](https://img.shields.io/badge/Version-1.0.0-green) ![ReaPack](https://img.shields.io/badge/ReaPack-Install-blueviolet)

**Background time tracking for REAPER projects, designed for billing and project management.**

## Overview

**Floop Bill The Pain Clock** is a time-tracking and billing utility that runs as a runs as a persistent background process inside REAPER. It monitors the time spent on your REAPER projects, completely decoupled from the graphical interface, ensuring time is tracked even if you close the UI. 

The tool features native Idle Detection, automatically halting tracking if you step away, and interacts with REAPER's transport status to manage tracking states dynamically.

## Overview 

<p align="center"> 
  <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-bill-the-pain-clock.png" target="_blank">
    <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-bill-the-pain-clock.png" width="700" alt="Floop Bill The Pain Clock Interface">
  </a>
</p>



## Key Features

*   **Background Daemon**: Time is counted in the background via a lightweight process. The ImGui UI can be closed at any time without halting the timers.
*   **Opt-in Tracking**: Tracking doesn't start automatically. You explicitly click "Start Tracking" per project.
*   **6-Phase Breakdown**: Categorize your time across specific tasks: Setup/Prep, Tracking, Editing, Mixing, Mastering, and Revisions.
*   **Idle Detection**: The clock pauses automatically after 5 minutes of total inactivity (no mouse, no keyboard). If REAPER is actively playing or recording, the clock continues counting regardless.
*   **Session Chronology**: Closing and reopening a project, or taking a long break, breaks your time into chronological "Sessions." You can add post-notes to each session.
*   **CSV Export**: Generate billing reports showing grand totals, phase breakdowns, and individual session notes.
*   **Custom Shortcuts**: Assign keyboard shortcuts to jump between phases or trigger a "Global Pause" across all projects.
*   

 **Install Prerequisites**:
 You will need the following dependencies installed via ReaPack:
   - **ReaImGui** (v0.10.2+)
   - **js_ReaScriptAPI** (Used exclusively for the CSV file save dialog)
    *   **Restart REAPER**.

2.  **Add the Repository**:
    *   Open **Extensions > ReaPack > Import Repositories.**
    *   Copy and paste this URL:
        https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
    *   Click **OK**.

3.  **Install the Script**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for `Floop Bill The Pain Clock`.
    *   Right-click > **Install**.
    *   Click **Apply**.
    *   
 4.  Run the script from the Action List. You will be prompted to enable the background Daemon on startup. **Restart REAPER** to finalize the Daemon installation.




## Changelog

### v1.0.0
* Initial Release 


## Support
If this script saves you time and helps you bill accurately, a coffee is always appreciated!

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20Development-orange?style=flat-square&logo=ko-fi)](https://ko-fi.com/floopsreaperscripts)
