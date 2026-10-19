# Changelog

## 0.3.1 - Unreleased

- Fixed Linux-exclusive cache-lock creation on Lua runtimes that reject `io.open(..., "wx")`; kept Windows atomic CreateNew fallback.
- Prevented stale-lock races from unlinking another process's live lock, and stopped age-only removal of lock files.
- Made Linux cache publication non-overwriting and enabled recovery of interrupted bitmap publications without replacing another instance's cache.
- Fixed mpv native-command failure detection and waveform overlay tracking so hover/autohide fully removes the waveform.
- Preserved hexadecimal uosc color values when reading configuration with whitespace around `=`.
- Added multi-process cache race, native mpv/FFmpeg smoke, error-handling, and autohide regression tests.
- Hardened Linux and Windows CI runners and switched Windows tool setup away from the unreliable Chocolatey feed.

## 0.3.0 - 2026-08-02

- Replaced the duration-dependent `showwavespic` analysis path with streaming FFmpeg peak metadata and Lua BGRA rendering.
- Added bounded-memory two-hour analysis and visual-parity release gates.
- Added generation phases, a configurable FFmpeg watchdog, and structured status errors.
- Added cache format 6 with `.bgra` plus commit-manifest validation.
- Enforced cache age/size targets throughout long sessions without a recurring background timer.
- Made disabled mode dormant and throttled autohide work to rendered mouse frames.
- Added complete observer, event, script-message, and key-binding teardown.
- Added same-process duplicate-instance protection.
- Added PID-aware cache locks that remain valid across suspend and wake.
- Added deterministic Linux/Windows runners, CI, stress tests, integration fixtures, and reproducible packaging.
