# uosc-waveform 0.2.0 Design

## Goal

Create a clean breaking release named `uosc-waveform` that preserves the validated uosc timeline integration while centering the waveform vertically and explicitly supporting local audio-only files.

## Naming

The installed script is `scripts/uosc-waveform.lua`, modules live under `scripts/uosc_waveform/`, and options live in `script-opts/uosc-waveform.conf`. Logs, bindings, script messages, diagnostics, documentation, cache directory, release files, and test imports use the same new name. There is no migration layer, compatibility alias, fallback to old files, or automatic cleanup of the old installation.

## Vertical centering

The waveform remains inside the animated effective uosc timeline. Chapter-marker clearance and progress-line clearance are converted to a single symmetric vertical inset equal to the larger clearance. The waveform is centered inside the remaining rectangle, so the empty space above and below is equal at every animation height. The source bitmap is never vertically cropped.

## Audio-only media

Local audio-only files with a selected audio track and finite duration are supported. Cover-art/image tracks do not classify an audio file as video. Stream selection, PTS alignment, delay handling, cache identity, FFmpeg generation, animation, and seekbar geometry use the same path as video containers. URLs, live sources, pipes, discs, unknown durations, and files without a selected audio track remain unsupported.

## Packaging

Release version is `0.2.0`. Users must remove the old `uosc-waveform.lua`, `uosc_waveform/`, and `uosc-waveform.conf` installation before copying the new package. The new cache namespace is independent from the old cache.

## Verification

Regression tests cover exact symmetric vertical margins at partial and full visibility, audio-only files with and without cover art, real FFmpeg generation from an audio fixture, absence of old runtime names, clean single-file bootstrap, package manifest, and Lua syntax.
