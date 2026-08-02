#!/usr/bin/env python3
"""Compare the production astats/Lua renderer with the v0.2 showwavespic envelope."""
from __future__ import annotations

import argparse
import math
import shutil
import statistics
import struct
import subprocess
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path

WIDTH = 512
HEIGHT = 64
RATE = 48_000
ANALYSIS_RATE = 8_000
COLOR = "#F2F2F2"
OPACITY = 0.38


@dataclass(frozen=True)
class Case:
    name: str
    input_path: Path
    timeline_duration: float
    audio_delay: float = 0.0
    timeline_offset: float = 0.0
    ff_index: int = 0
    audio_ordinal: int = 0


def run(args: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(args, stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace")
        raise RuntimeError(f"command failed ({result.returncode}): {args!r}\n{detail}")
    return result


def write_wav(path: Path, duration: float, sample_fn) -> None:
    frames = int(round(duration * RATE))
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        block = bytearray()
        for index in range(frames):
            value = max(-1.0, min(1.0, float(sample_fn(index / RATE, index))))
            block.extend(struct.pack("<h", int(round(value * 32767))))
            if len(block) >= 64 * 1024:
                output.writeframesraw(block)
                block.clear()
        if block:
            output.writeframesraw(block)


def premultiplied_rgba() -> str:
    alpha = round(OPACITY * 255)
    rgb = tuple(round(value * alpha / 255) for value in (0xF2, 0xF2, 0xF2))
    return f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}{alpha:02X}"


def shift_filter(delay: float) -> str | None:
    if abs(delay) < 1e-9:
        return None
    if delay > 0:
        return f"asetpts=PTS+{delay:.9g}/TB"
    return f"asetpts=PTS-{abs(delay):.9g}/TB"


def legacy_argv(ffmpeg: str, case: Case, output: Path) -> list[str]:
    filters: list[str] = []
    shift = shift_filter(case.audio_delay + case.timeline_offset)
    if shift:
        filters.append(shift)
    filters.extend([
        "aformat=channel_layouts=mono",
        f"aresample={ANALYSIS_RATE}:async=1:first_pts=0",
        f"apad=whole_dur={case.timeline_duration:.9g}",
        f"atrim=duration={case.timeline_duration:.9g}",
        f"showwavespic=s={WIDTH}x{HEIGHT}:split_channels=0:colors={premultiplied_rgba()}:scale=sqrt:draw=scale:filter=peak",
        "format=bgra[wave]",
    ])
    graph = f"[0:{case.ff_index}]" + ",".join(filters)
    return [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-i", str(case.input_path), "-filter_complex", graph, "-map", "[wave]",
        "-frames:v", "1", "-an", "-sn", "-dn", "-f", "rawvideo",
        "-pix_fmt", "bgra", str(output),
    ]


def production_argv(lua: str, root: Path, case: Case) -> list[str]:
    helper = root / "tests/helpers/emit_ffmpeg_audio_argv.lua"
    result = run([
        lua, str(helper), str(root), str(case.input_path),
        str(case.timeline_duration), str(WIDTH), str(ANALYSIS_RATE),
        str(case.audio_delay), str(case.timeline_offset),
        str(case.ff_index), str(case.audio_ordinal),
    ], capture=True)
    return [part.decode("utf-8") for part in result.stdout.split(b"\0") if part]


def alpha_envelope(path: Path) -> list[int]:
    data = path.read_bytes()
    expected = WIDTH * HEIGHT * 4
    if len(data) != expected:
        raise AssertionError(f"{path.name}: expected {expected} bytes, got {len(data)}")
    result: list[int] = []
    for x in range(WIDTH):
        count = 0
        for y in range(HEIGHT):
            if data[(y * WIDTH + x) * 4 + 3] != 0:
                count += 1
        result.append(count)
    return result


def correlation(left: list[float], right: list[float]) -> float:
    if left == right:
        return 1.0
    left_mean = statistics.fmean(left)
    right_mean = statistics.fmean(right)
    left_variance = sum((value - left_mean) ** 2 for value in left)
    right_variance = sum((value - right_mean) ** 2 for value in right)
    if left_variance < 1e-9 or right_variance < 1e-9:
        return 0.0
    numerator = sum((a - left_mean) * (b - right_mean) for a, b in zip(left, right))
    return numerator / math.sqrt(left_variance * right_variance)


def smooth(values: list[int], radius: int = 2) -> list[float]:
    result: list[float] = []
    for index in range(len(values)):
        start = max(0, index - radius)
        stop = min(len(values), index + radius + 1)
        result.append(sum(values[start:stop]) / (stop - start))
    return result


def active_clusters(values: list[int]) -> list[float]:
    clusters: list[float] = []
    start: int | None = None
    for index, value in enumerate(values + [0]):
        if value > 0 and start is None:
            start = index
        elif value == 0 and start is not None:
            clusters.append((start + index - 1) / 2)
            start = None
    return clusters


def shape_score(left: list[int], right: list[int]) -> tuple[float, float | None]:
    left_active = sum(value > 0 for value in left)
    right_active = sum(value > 0 for value in right)
    if max(left_active, right_active) <= max(8, len(left) // 10):
        left_clusters = active_clusters(left)
        right_clusters = active_clusters(right)
        if len(left_clusters) != len(right_clusters):
            return 0.0, math.inf
        maximum_shift = max((abs(a - b) for a, b in zip(left_clusters, right_clusters)), default=0.0)
        return max(0.0, 1.0 - maximum_shift / len(left)), maximum_shift
    if statistics.pvariance(left) < 1.0 or statistics.pvariance(right) < 1.0:
        maximum_difference = max(abs(a - b) for a, b in zip(left, right))
        return (1.0 if maximum_difference <= 2 else 0.0), None
    return correlation(smooth(left), smooth(right)), None

def percentile(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)]


def make_cases(work: Path, ffmpeg: str) -> list[Case]:
    sine = lambda hz, amp=0.75: lambda t, _i: amp * math.sin(2 * math.pi * hz * t)
    fixtures: list[tuple[str, float, object]] = [
        ("silence", 6.0, lambda _t, _i: 0.0),
        ("impulse", 6.0, lambda _t, i: 1.0 if i in (RATE, RATE * 4) else 0.0),
        ("ramped-sine", 6.0, lambda t, _i: min(1.0, t / 6.0) * 0.9 * math.sin(2 * math.pi * 330 * t)),
        ("late-start", 6.0, lambda t, _i: 0.0 if t < 2.0 else 0.8 * math.sin(2 * math.pi * 440 * t)),
        ("middle-gap", 6.0, lambda t, _i: 0.0 if 2.0 <= t < 4.0 else 0.7 * math.sin(2 * math.pi * 550 * t)),
        ("short-audio", 3.0, sine(660, 0.65)),
    ]
    paths: dict[str, Path] = {}
    for name, duration, fn in fixtures:
        path = work / f"{name}.wav"
        write_wav(path, duration, fn)
        paths[name] = path

    cases = [
        Case("silence", paths["silence"], 6.0),
        Case("impulse", paths["impulse"], 6.0),
        Case("ramped-sine", paths["ramped-sine"], 6.0),
        Case("late-start", paths["late-start"], 6.0),
        Case("middle-gap", paths["middle-gap"], 6.0),
        Case("short-audio", paths["short-audio"], 6.0),
        Case("positive-delay", paths["short-audio"], 6.0, audio_delay=1.0),
        Case("negative-delay", paths["late-start"], 6.0, audio_delay=-1.0),
    ]

    track_a = work / "track-a.wav"
    track_b = work / "track-b.wav"
    write_wav(track_a, 6.0, sine(220, 0.25))
    write_wav(track_b, 6.0, lambda t, _i: (0.2 + 0.7 * t / 6.0) * math.sin(2 * math.pi * 880 * t))
    multi = work / "two-tracks.mkv"
    run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(track_a), "-i", str(track_b), "-map", "0:a", "-map", "1:a",
        "-c:a", "flac", str(multi),
    ])
    cases.extend([
        Case("multi-track-a", multi, 6.0, ff_index=0, audio_ordinal=0),
        Case("multi-track-b", multi, 6.0, ff_index=1, audio_ordinal=1),
    ])

    cover = work / "cover.ppm"
    cover.write_bytes(b"P6\n16 16\n255\n" + bytes([40, 120, 200]) * (16 * 16))
    m4a = work / "audio-with-cover.m4a"
    run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(track_b), "-i", str(cover), "-map", "0:a", "-map", "1:v",
        "-c:a", "aac", "-b:a", "64k", "-c:v", "mjpeg",
        "-disposition:v:0", "attached_pic", str(m4a),
    ])
    cases.append(Case("m4a-cover-art", m4a, 6.0, ff_index=0, audio_ordinal=0))
    return cases


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--lua", default="lua")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    if not shutil.which(args.lua):
        raise SystemExit(f"Lua executable not found: {args.lua}")
    if not shutil.which(args.ffmpeg):
        raise SystemExit(f"FFmpeg executable not found: {args.ffmpeg}")

    temporary = Path(tempfile.mkdtemp(prefix="uosc-waveform-parity-"))
    try:
        cases = make_cases(temporary, args.ffmpeg)
        failures: list[str] = []
        for case in cases:
            legacy = temporary / f"{case.name}.legacy.bgra"
            metadata = temporary / f"{case.name}.metadata.txt"
            rendered = temporary / f"{case.name}.new.bgra"
            run(legacy_argv(args.ffmpeg, case, legacy))
            production = production_argv(args.lua, root, case)
            metadata.write_bytes(run(production, capture=True).stdout)
            run([
                args.lua, str(root / "tests/helpers/render_peak_metadata.lua"),
                str(root), str(metadata), str(rendered), str(case.timeline_duration),
                str(WIDTH), str(HEIGHT), COLOR, str(OPACITY),
            ])
            old_envelope = alpha_envelope(legacy)
            new_envelope = alpha_envelope(rendered)
            differences = [abs(a - b) for a, b in zip(old_envelope, new_envelope)]
            score, sparse_shift = shape_score(old_envelope, new_envelope)
            median = float(statistics.median(differences))
            p95 = percentile(differences, 0.95)
            shift_text = f" sparse_shift={sparse_shift:.1f}px" if sparse_shift is not None else ""
            print(f"{case.name}: shape_score={score:.6f} median_diff={median:.1f}px p95={p95}px{shift_text}")
            if score < 0.98 or median > 2 or p95 > 5 or (sparse_shift is not None and sparse_shift > 4):
                failures.append(
                    f"{case.name}: score={score:.6f}, median={median}, p95={p95}, sparse_shift={sparse_shift}"
                )
        if failures:
            raise AssertionError("visual parity failed:\n" + "\n".join(failures))
        print(f"PASS ffmpeg_visual_parity cases={len(cases)}")
        return 0
    finally:
        if args.keep_workdir:
            print(f"workdir={temporary}")
        else:
            shutil.rmtree(temporary, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
