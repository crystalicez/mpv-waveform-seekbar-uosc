# Changelog

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
