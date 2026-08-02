# Windows release validation

Run this checklist against the exact extracted release ZIP, not the source directory, when validating `v0.3.0` on Windows or investigating a release regression.

## Test environment

Record:

- Windows version and build
- CPU and installed RAM
- mpv version
- uosc version
- FFmpeg version and build source
- GPU and video output
- `uosc-waveform.conf`
- Relevant `uosc.conf`
- Other scripts that touch audio, overlays, or `lavfi-complex`

## Media matrix

Test uncached and cached playback for:

- MP4 with one audio track
- MP4 with multiple audio tracks
- M4A
- M4A with attached cover art
- WAV, FLAC, MP3, Opus, and Ogg
- External audio
- Positive and negative `audio-delay`
- Audio with a late start, a middle timestamp gap, and an early ending
- Audio selected by a visualizer through `lavfi-complex`

For every item verify `GENERATING → READY_HIDDEN/READY_VISIBLE`, timeline alignment, vertical centering, track switching, seeking, and clean close.

## Resource matrix

Collect mpv and FFmpeg CPU, private working set, handles, process count, cache bytes, and auxiliary files for:

- Startup without media
- Cache hit
- Uncached 1-, 10-, 60-, and 120-minute audio
- Two simultaneous uncached 60-minute instances
- Mouse stationary and rapid movement
- Enabled and disabled modes

Acceptance targets:

- Two-hour FFmpeg peak private working set below 128 MiB where the selected FFmpeg build permits it
- No more than one FFmpeg child per mpv instance
- No periodic CPU activity attributable to the script while disabled and idle
- No monotonic mpv private-memory or handle growth
- Cache returns to its configured target after a cleanup trigger

## Lifecycle matrix

Exercise:

- Change file while FFmpeg is analyzing
- Rapid audio-track switching
- Repeated `Alt+w` toggling
- Seek bursts
- Close mpv during analysis
- Playlist containing at least 300 files
- Suspend for more than `stale_lock_seconds`, then wake
- Graceful shutdown and forced termination

Verify that no orphan FFmpeg process, stale overlay, `.tmp`, `.meta.tmp`, or dead-owner `.lock` remains.

## Eight-hour soak

Example:

```powershell
powershell -ExecutionPolicy Bypass -File tools\windows-soak.ps1 `
  -MpvPath C:\Tools\mpv\mpv.exe `
  -ConfigDir C:\Users\Name\AppData\Roaming\mpv `
  -MediaPaths C:\Media\test-a.m4a,C:\Media\test-b.mp4 `
  -DurationHours 8 `
  -SampleIntervalSeconds 600
```

The script writes CSV samples and a PASS/FAIL summary. Review the graph/trend manually as well; a flat end-to-end value can hide growth followed by cleanup.

## Validation record

Attach:

- Test environment
- Completed media/lifecycle matrix
- Soak CSV and summary
- Peak FFmpeg memory measurements
- Screenshots for MP4 and audio-only timelines
- Any deviations and their disposition

Treat crashes, hangs, orphan processes, stale overlays, cache drift, unexplained monotonic resource growth, or a failed media/lifecycle case as release-blocking regressions.
