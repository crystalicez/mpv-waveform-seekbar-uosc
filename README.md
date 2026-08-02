# uosc-waveform

A third-party mpv Lua script that generates a full-track audio waveform with FFmpeg and displays it inside the [uosc](https://github.com/tomasklaen/uosc) timeline.

The waveform follows uosc's seekbar geometry and mouse-proximity animation while leaving all seeking, chapters, thumbnails, A–B loops, and other timeline interactions under uosc's control.

> Current release: **v0.2.0**  
> Primary supported platform: **Windows 10/11**

## Highlights

- Full-track waveform for video and audio-only files
- Supports multiple embedded or external audio tracks
- Preserves audio timestamps, gaps, stream offsets, and `audio-delay`
- Short audio is padded with silence on the media timeline and is never stretched
- Animation follows uosc's timeline and controls proximity behavior
- One cached BGRA bitmap overlay; no redraw tied to playback position
- Asynchronous FFmpeg analysis does not pause playback
- Handles spaces, Unicode filenames, Thai/Japanese text, emoji, and Windows shell metacharacters
- Startup is silent by default

## How it works

1. The script reads the currently selected audio track from mpv.
2. FFmpeg renders the complete track to a transparent BGRA waveform bitmap.
3. The bitmap is cached per media file, audio track, timeline mapping, color, and analysis settings.
4. A single mpv bitmap overlay is resized and positioned over the uosc timeline.
5. uosc remains responsible for all mouse and seekbar interaction.

The first load of a file may take a moment because FFmpeg analyzes the full selected audio stream. Later loads use the cache.

## Requirements

| Component | Requirement |
|---|---|
| Operating system | Windows 10 or Windows 11 |
| mpv | 0.41.0 stable or a compatible recent development build |
| uosc | 5.12.x |
| FFmpeg | A build containing the `showwavespic` filter |
| Media | Local, seekable file with a known positive duration and a selected audio track |

Network URLs, YouTube/live streams, stdin, pipes, DVD, and Blu-ray sources are intentionally skipped.

## Installation

Download the latest release ZIP from the repository's **Releases** page.

### Standard mpv installation

Copy the contents of the ZIP's `portable_config` directory into:

```text
%APPDATA%\mpv\
```

The resulting layout should be:

```text
%APPDATA%\mpv\
├─ scripts\
│  ├─ uosc-waveform.lua
│  └─ uosc_waveform\
│     ├─ cache.lua
│     ├─ controller.lua
│     ├─ ffmpeg.lua
│     ├─ geometry.lua
│     ├─ media.lua
│     ├─ mpv_compat.lua
│     ├─ options.lua
│     ├─ overlay.lua
│     ├─ util.lua
│     └─ windows_lock.lua
└─ script-opts\
   └─ uosc-waveform.conf
```

Restart mpv after installation.

### Portable mpv installation

Extract the release ZIP next to `mpv.exe`. The included `portable_config` directory is already arranged correctly.

### Audio-only files

mpv needs a visible window for uosc and the waveform overlay. Add this to `mpv.conf` when playing MP3, FLAC, M4A, Opus, Ogg, WAV, and other audio-only files:

```ini
force-window=yes
```

Audio files with embedded cover art are supported.

## FFmpeg setup

When FFmpeg is available in `PATH`, keep the default:

```ini
ffmpeg_path=ffmpeg
```

To use an explicit executable:

```ini
ffmpeg_path=C:\Tools\FFmpeg\bin\ffmpeg.exe
```

Do not wrap the path in shell quotes. It is passed to mpv as one subprocess argument.

Confirm that the required filter is available:

```bat
ffmpeg.exe -hide_banner -h filter=showwavespic
```

## Controls

| Key | Action |
|---|---|
| `Alt+w` | Toggle the waveform |
| `Alt+Shift+w` | Show script state, active config directory, and log path |

The toggle is also available as a script message:

```text
script-message uosc-waveform-toggle
```

The built-in key binding can be replaced in `input.conf`:

```text
Alt+w script-message uosc-waveform-toggle
```

## Configuration

Configuration file:

```text
script-opts/uosc-waveform.conf
```

A practical minimal configuration:

```ini
enabled=yes
ffmpeg_path=ffmpeg
opacity=0.38
color_mode=auto
startup_osd=no
log_level=warn
```

### Display options

| Option | Default | Accepted values | Description |
|---|---:|---|---|
| `enabled` | `yes` | yes/no | Start with the waveform enabled |
| `opacity` | `0.38` | 0–1 | Premultiplied waveform opacity |
| `color_mode` | `auto` | auto/light/dark | Select waveform contrast mode |
| `light_color` | `#101010` | `#RRGGBB` | Waveform color for light UI backgrounds |
| `dark_color` | `#F2F2F2` | `#RRGGBB` | Waveform color for dark UI backgrounds |
| `displayed_height_ratio` | `0.78` | 0.05–1 | Fraction of available timeline height used by the waveform |
| `reserved_marker_ratio` | `0.20` | 0–0.8 | Clearance reserved for uosc timeline markers |
| `reserved_progress_px` | `2` | 0–64 | Minimum clearance for the minimized progress line |
| `minimum_timeline_width` | `320` | 1–16384 | Hide the waveform below this OSD width |
| `overlay_id` | `63` | 0–63 | mpv bitmap-overlay ID used by the script |

### Analysis and cache options

| Option | Default | Accepted values | Description |
|---|---:|---|---|
| `ffmpeg_path` | `ffmpeg` | executable path | FFmpeg executable |
| `source_width` | `4096` | 256–16384 | Width of the cached waveform bitmap |
| `source_height` | `128` | 16–512 | Height of the cached waveform bitmap |
| `analysis_sample_rate` | `8000` | 1000–192000 | Mono sample rate used for waveform analysis |
| `cache_dir` | `~~/cache/uosc-waveform` | local directory | Waveform cache directory |
| `max_cache_age_days` | `60` | 1–3650 | Cache age cleanup target |
| `max_cache_mb` | `512` | 64–1048576 | Cache size cleanup target |
| `stale_lock_seconds` | `900` | 30–604800 | Age at which an abandoned generation lock is considered stale |
| `lock_poll_ms` | `500` | 100–5000 | Poll interval while another mpv instance generates the same waveform |

### Runtime options

| Option | Default | Accepted values | Description |
|---|---:|---|---|
| `resize_debounce_ms` | `120` | 0–5000 | Debounce for window resize events |
| `mouse_update_interval_ms` | `16` | 0–1000 | Mouse-proximity update throttle; `0` updates on every event |
| `media_debounce_ms` | `250` | 0–5000 | Coalesces rapid file and track property changes |
| `compatibility` | `uosc-5.12` | adapter name | uosc geometry adapter |
| `adapter_override` | empty | adapter name | Explicit adapter override for testing |
| `startup_osd` | `no` | yes/no | Show a load confirmation banner at startup |
| `diagnostic_log` | `yes` | yes/no | Write the internal diagnostic log |
| `log_level` | `warn` | error/warn/info/debug | Runtime and diagnostic logging threshold |

Invalid, non-finite, or out-of-range values fall back to defaults or are clamped to safe ranges.

## Timeline accuracy

The waveform is mapped to the same media time axis as the uosc seekbar:

- Audio that begins later leaves empty space at the beginning.
- Audio that ends early leaves empty space at the end.
- Audio longer than the media timeline is cropped at the timeline boundary.
- Audio is never compressed or stretched to fill the seekbar.
- Positive and negative `audio-delay` values shift the waveform accordingly.
- `rebase-start-time=no` preserves leading demuxer timeline space.

## Multiple audio tracks

The script follows mpv's active `aid` and supports:

- Multiple embedded audio streams
- External audio files
- Runtime track switching
- FFmpeg stream index selection
- Source-scoped ordinal fallback when stream indexes are unavailable

Switching tracks invalidates the active waveform and loads or generates the correct cached result.

## Cache behavior

Default cache location:

```text
<mpv-config>\cache\uosc-waveform\
```

Each cached BGRA payload is validated against:

```text
source_width × source_height × 4 bytes
```

The cache key includes the source identity, selected audio track, timeline mapping, colors, opacity, and analysis settings. Concurrent mpv instances coordinate through generation locks and publish completed output safely.

## Troubleshooting

### No waveform appears

1. Press `Alt+Shift+w` and check the reported state.
2. Confirm that FFmpeg is available and supports `showwavespic`.
3. Confirm that the file is local, seekable, and has a selected audio track.
4. For audio-only files, enable `force-window=yes`.
5. Make sure uosc's timeline is enabled and the mpv window is wide enough.

Normal ready states include:

```text
GENERATING
READY_HIDDEN
READY_VISIBLE
```

### Enable detailed logging

Set:

```ini
log_level=debug
diagnostic_log=yes
```

Restart mpv, reproduce the issue, and inspect:

```text
<mpv-config>\uosc-waveform.log
```

The diagnostic log rotates at 2 MiB to:

```text
uosc-waveform.log.old
```

### Script does not load

Run:

```text
diagnose-uosc-waveform.cmd
```

It creates `uosc-waveform-diagnostic-report.txt` with environment and file-layout information.

### Overlay conflict

The default bitmap overlay ID is `63`. Another bitmap-overlay script using the same ID can replace the waveform. Change this setting when needed:

```ini
overlay_id=62
```

## Known limitations

- Bitmap overlays are rendered above uosc's ASS layer. Exact compositing would require changes inside uosc itself.
- uosc does not expose a public timeline-state API. Normal mouse proximity and cursor-leave behavior are mirrored, but private states such as `flash-timeline`, `toggle-progress`, speed dragging, and every forced-visibility transition cannot be observed perfectly.
- The first generation decodes the complete selected audio stream.
- Runtime audio filters, tempo processing, equalizers, `lavfi-complex`, and mixed multi-track output are not represented. The waveform represents the selected source stream plus global `audio-delay`.
- Complex ordered Matroska editions and linked segments are best effort.
- External audio with a different timestamp origin may require manual `audio-delay` adjustment.
- Replacing a file in place while preserving both size and modification time can reuse a stale cache entry.
- A generation that exceeds `stale_lock_seconds` may duplicate work, although cache publication remains race-safe.

## Project structure

```text
portable_config/
├─ scripts/
│  ├─ uosc-waveform.lua
│  └─ uosc_waveform/
└─ script-opts/
   └─ uosc-waveform.conf

tests/
examples/
diagnose-uosc-waveform.cmd
diagnose-uosc-waveform.ps1
```

## Contributing

Bug reports should include:

- mpv version
- uosc version
- FFmpeg version
- Relevant `uosc.conf` timeline settings
- `uosc-waveform.conf`
- The state shown by `Alt+Shift+w`
- The relevant section of `uosc-waveform.log` with `log_level=debug`

Please avoid uploading private media files. A small synthetic sample that reproduces the issue is preferred.

## License

Released under the [MIT License](LICENSE).

This project is a third-party extension and is not part of or officially affiliated with uosc.
