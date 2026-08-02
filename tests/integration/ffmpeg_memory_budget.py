#!/usr/bin/env python3
"""Linux CI resource gate for the two-hour production analyzer."""
from __future__ import annotations

import argparse
import platform
import resource
import struct
import subprocess
import tempfile
import time
from pathlib import Path

DURATION = 7200
SAMPLE_RATE = 8000
WIDTH = 4096
HEIGHT = 128
MAX_RSS_KIB = 128 * 1024


def sparse_silence_wav(path: Path) -> None:
    data_size = DURATION * SAMPLE_RATE * 2
    riff_size = 36 + data_size
    header = b"".join([
        b"RIFF", struct.pack("<I", riff_size), b"WAVE",
        b"fmt ", struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16),
        b"data", struct.pack("<I", data_size),
    ])
    with path.open("wb") as output:
        output.write(header)
        output.seek(len(header) + data_size - 1)
        output.write(b"\0")


def run_checked(args: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(args, stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode("utf-8", "replace"))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--lua", default="lua")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    args = parser.parse_args()
    if platform.system() != "Linux":
        print("SKIP ffmpeg_memory_budget: Linux ru_maxrss gate only")
        return 0

    root = args.root.resolve()
    with tempfile.TemporaryDirectory(prefix="uosc-waveform-memory-") as directory:
        work = Path(directory)
        source = work / "two-hours-silence.wav"
        metadata = work / "metadata.txt"
        output = work / "waveform.bgra"
        sparse_silence_wav(source)
        helper = root / "tests/helpers/emit_ffmpeg_audio_argv.lua"
        encoded = run_checked([
            args.lua, str(helper), str(root), str(source), str(DURATION),
            str(WIDTH), str(SAMPLE_RATE), "0", "0", "0", "0",
        ], capture=True).stdout
        argv = [part.decode("utf-8") for part in encoded.split(b"\0") if part]
        started = time.monotonic()
        result = run_checked(argv, capture=True)
        elapsed = time.monotonic() - started
        metadata.write_bytes(result.stdout)
        run_checked([
            args.lua, str(root / "tests/helpers/render_peak_metadata.lua"),
            str(root), str(metadata), str(output), str(DURATION), str(WIDTH),
            str(HEIGHT), "#F2F2F2", "0.38",
        ])
        expected_size = WIDTH * HEIGHT * 4
        if output.stat().st_size != expected_size:
            raise AssertionError(f"expected {expected_size} BGRA bytes")
        maximum_rss_kib = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        if maximum_rss_kib > MAX_RSS_KIB:
            raise AssertionError(
                f"two-hour analyzer RSS {maximum_rss_kib / 1024:.1f} MiB exceeds {MAX_RSS_KIB / 1024:.0f} MiB"
            )
        print(
            f"PASS ffmpeg_memory_budget duration={DURATION}s "
            f"max_rss={maximum_rss_kib / 1024:.1f}MiB elapsed={elapsed:.2f}s"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
