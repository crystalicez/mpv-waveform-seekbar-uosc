# uosc-waveform 0.2.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a clean `uosc-waveform 0.2.0` breaking release with symmetric waveform placement and verified local audio-only playback support.

**Architecture:** Rename the runtime namespace atomically rather than adding aliases. Keep the existing media/cache/FFmpeg/controller boundaries, change geometry to use symmetric vertical padding, and add audio-only regression and integration fixtures around the existing media pipeline.

**Tech Stack:** mpv Lua API, Lua 5.2/5.3-compatible modules, FFmpeg `showwavespic`, raw premultiplied BGRA overlays, PowerShell Windows path fallbacks, ZIP packaging.

## Global Constraints

- Exact installed script name: `uosc-waveform`.
- Exact module namespace: `uosc_waveform`.
- Release version: `0.2.0`.
- No migration, old-name fallback, compatibility alias, or automatic cleanup.
- Preserve one static bitmap overlay and existing uosc proximity animation.
- Preserve local-file-only policy and asynchronous FFmpeg generation.

---

### Task 1: Breaking namespace rename

**Files:**
- Rename: `portable_config/scripts/uosc-waveform.lua` → `portable_config/scripts/uosc-waveform.lua`
- Rename: `portable_config/scripts/uosc_waveform/` → `portable_config/scripts/uosc_waveform/`
- Rename: `portable_config/script-opts/uosc-waveform.conf` → `portable_config/script-opts/uosc-waveform.conf`
- Modify: all runtime Lua, tests, diagnostics, examples, and README

**Interfaces:**
- Consumes: existing module APIs unchanged except module prefix.
- Produces: `require("uosc_waveform.<module>")`, script option namespace `uosc-waveform`, messages `uosc-waveform-*`, log `uosc-waveform.log`.

- [ ] Write a test that scans packaged runtime files and fails on `uosc_waveform`, `uosc-waveform`, or `uosc-waveform`, except the explicit uninstall note in README.
- [ ] Run the test and verify it fails on the old tree.
- [ ] Rename files/directories and update all runtime identifiers and visible names.
- [ ] Run bootstrap, syntax, and namespace tests.

### Task 2: Symmetric vertical placement

**Files:**
- Modify: `portable_config/scripts/uosc_waveform/geometry.lua`
- Modify: `tests/geometry_proximity.lua`
- Create: `tests/geometry_vertical_center.lua`

**Interfaces:**
- Consumes: marker clearance, progress clearance, animated effective timeline size.
- Produces: rectangle with equal top and bottom empty margins and no source crop.

- [ ] Add failing full-height and partial-height assertions that top and bottom margins are identical.
- [ ] Run the geometry tests and verify the old asymmetric calculation fails.
- [ ] Replace independent top/bottom reserves with `symmetric_inset = max(marker_px, progress_px)` and center within the remainder.
- [ ] Run all geometry/controller animation tests.

### Task 3: Explicit audio-only support

**Files:**
- Modify: `portable_config/scripts/uosc_waveform/media.lua` only if tests expose a gap
- Create: `tests/media_audio_only.lua`
- Create: `tests/controller_audio_only.lua`
- Create during verification: synthetic WAV/FLAC fixture

**Interfaces:**
- Consumes: local path, finite duration, selected audio track, optional cover-art video track.
- Produces: supported media info with `media_type="audio"` and valid FFmpeg mapping.

- [ ] Add tests for plain audio, audio with cover art, `aid=auto` selected fallback, no selected audio, and unknown duration.
- [ ] Add controller test proving audio-only reaches `GENERATING`/ready instead of `UNSUPPORTED`.
- [ ] Run tests and fix only demonstrated gaps.
- [ ] Generate a real audio fixture and run the module-built FFmpeg argv; validate BGRA size.

### Task 4: Release cleanup and packaging

**Files:**
- Modify: `README.md`, `diagnose-uosc-waveform.cmd`, `diagnose-uosc-waveform.ps1`, `examples/input.conf`
- Create: release ZIP, hotfix ZIP, checksum, verification report

**Interfaces:**
- Produces: clean package containing only new names and explicit old-installation removal instructions.

- [ ] Update installation, debug, bindings, log, and uninstall instructions.
- [ ] Run every Lua test and compile every runtime Lua file.
- [ ] Scan package contents and file bodies for forbidden old runtime names.
- [ ] Build ZIPs, compare extracted files byte-for-byte, run ZIP integrity checks, and record SHA-256.
