#!/usr/bin/env python3
"""Native Linux mpv + FFmpeg cache smoke, including competing players and crash recovery.

No GUI or uosc dependency is needed to exercise the production Lua entrypoint,
media detection, asynchronous FFmpeg, cache lock and manifest filesystem path.
This is not a visual-overlay acceptance test.
"""
from __future__ import annotations

import argparse
import hashlib
import math
import shutil
import subprocess
import tempfile
import time
import wave
from pathlib import Path


def audio_fixture(path: Path) -> None:
    sample_rate = 16000
    count = sample_rate * 4
    frames = bytearray()
    for index in range(count):
        level = int(11000 * math.sin(2 * math.pi * 300 * index / sample_rate))
        frames += level.to_bytes(2, "little", signed=True)
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(sample_rate)
        audio.writeframes(frames)


def start_player(mpv: str, entry: Path, temp: Path, cache: Path, audio: Path, label: str):
    config = temp / ("config-" + label)
    opts = config / "script-opts"
    opts.mkdir(parents=True)
    (opts / "uosc-waveform.conf").write_text(
        "\n".join(
            [
                "enabled=yes",
                "cache_dir=" + str(cache),
                "ffmpeg_path=ffmpeg",
                "source_width=256",
                "source_height=16",
                "media_debounce_ms=0",
                "generation_timeout_seconds=30",
                "diagnostic_log=yes",
                "log_level=debug",
                "",
            ]
        ),
        encoding="utf-8",
    )
    logfile = temp / ("mpv-" + label + ".log")
    argv = [
        mpv,
        "--no-terminal",
        "--no-osc",
        "--vo=null",
        "--ao=null",
        "--audio-display=no",
        "--force-window=no",
        "--idle=yes",
        "--keep-open=yes",
        "--pause=yes",
        "--config-dir=" + str(config),
        "--script=" + str(entry),
        "--log-file=" + str(logfile),
        str(audio),
    ]
    player = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return player, logfile


def await_cache(cache: Path, players: list[tuple[subprocess.Popen, Path]], seconds: float) -> tuple[Path, Path]:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        for player, logfile in players:
            if player.poll() is not None:
                raise RuntimeError(f"mpv exited unexpectedly ({player.returncode})\n{tail(logfile)}")
        manifests = sorted(cache.glob("*-256x16.meta"))
        if len(manifests) == 1:
            meta = manifests[0]
            raw = meta.with_suffix(".bgra")
            manifest = meta.read_text(encoding="utf-8")
            if raw.is_file() and raw.stat().st_size == 256 * 16 * 4 and (
                "cache-format=6" in manifest
                and "size=16384" in manifest
                and "width=256" in manifest
                and "height=16" in manifest
            ):
                return raw, meta
        time.sleep(0.1)
    diagnostics = "\n".join(f"[{logfile}]\n{tail(logfile)}" for _, logfile in players)
    raise RuntimeError(f"timed out waiting for native mpv cache publication\n{diagnostics}")


def tail(path: Path) -> str:
    if not path.exists():
        return "(no mpv logfile)"
    return path.read_text(encoding="utf-8", errors="replace")[-9000:]


def stop_players(players: list[tuple[subprocess.Popen, Path]]) -> None:
    for player, _ in players:
        if player.poll() is None:
            player.terminate()
    for player, _ in players:
        try:
            player.wait(timeout=8)
        except subprocess.TimeoutExpired:
            player.kill()
            player.wait(timeout=8)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--mpv", default="mpv")
    args = parser.parse_args()

    if not shutil.which(args.mpv):
        raise RuntimeError("mpv executable is required for native smoke test")
    entry = args.root.resolve() / "portable_config/scripts/uosc-waveform.lua"
    if not entry.is_file():
        raise RuntimeError(f"missing entrypoint: {entry}")

    with tempfile.TemporaryDirectory(prefix="uosc-native-mpv-") as directory:
        temp = Path(directory)
        cache = temp / "shared cache ไทย"
        cache.mkdir()
        audio = temp / "audio ไทย space.wav"
        audio_fixture(audio)
        players: list[tuple[subprocess.Popen, Path]] = []
        try:
            for label in ("first", "second"):
                players.append(start_player(args.mpv, entry, temp, cache, audio, label))
            raw, meta = await_cache(cache, players, 55)
            before = hashlib.sha256(raw.read_bytes()).hexdigest()
            assert len(list(cache.glob("*-256x16.meta"))) == 1
            print("PASS native mpv: concurrent players created one validated cache entry", flush=True)
        except Exception:
            for _, logfile in players:
                print(f"--- {logfile} ---\n{tail(logfile)}", flush=True)
            raise
        finally:
            stop_players(players)

        # Simulate an interrupted publisher: its bitmap is complete, but the
        # commit manifest was never written. The dead owner's lock prevents
        # destructive canonical cleanup by the new instance.
        meta.unlink()
        lock = raw.with_suffix(".lock")
        lock.write_text("created=1\nowner=dead-mpv\npid=0\n", encoding="utf-8")
        recovered = [start_player(args.mpv, entry, temp, cache, audio, "recovery")]
        try:
            restored_raw, restored_meta = await_cache(cache, recovered, 55)
            assert restored_raw == raw and restored_meta == meta
            assert hashlib.sha256(raw.read_bytes()).hexdigest() == before, (
                "orphan recovery unexpectedly replaced the original bitmap"
            )
            assert lock.exists(), "stale lock should not be unlinked by another mpv"
            print("PASS native mpv: orphan manifest recovered without overwriting bitmap", flush=True)
        except Exception:
            for _, logfile in recovered:
                print(f"--- {logfile} ---\n{tail(logfile)}", flush=True)
            raise
        finally:
            stop_players(recovered)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
