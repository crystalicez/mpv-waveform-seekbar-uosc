#!/usr/bin/env python3
"""Build and verify a deterministic uosc-waveform release ZIP."""
from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import tempfile
import zipfile
from pathlib import Path

INCLUDED_TOP_LEVEL = (
    "LICENSE",
    "README.md",
    "CHANGELOG.md",
    "diagnose-uosc-waveform.cmd",
    "diagnose-uosc-waveform.ps1",
    "examples",
    "portable_config",
)
FORBIDDEN_NAMES = ("waveform-preview", "waveform_preview", ".log", ".tmp", ".lock", "__pycache__")
FORBIDDEN_RUNTIME_CONTENT = ("waveform-preview", "waveform_preview", "showwavespic")


def runtime_version(root: Path) -> str:
    entry = (root / "portable_config/scripts/uosc-waveform.lua").read_text(encoding="utf-8")
    match = re.search(r'local SCRIPT_VERSION = "([^"]+)"', entry)
    if not match:
        raise ValueError("SCRIPT_VERSION not found")
    return match.group(1)


def selected_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for name in INCLUDED_TOP_LEVEL:
        path = root / name
        if not path.exists():
            if name == "CHANGELOG.md":
                continue
            raise FileNotFoundError(path)
        if path.is_file():
            files.append(path)
        else:
            files.extend(item for item in path.rglob("*") if item.is_file())
    return sorted(files, key=lambda item: item.relative_to(root).as_posix())


def verify_source(root: Path, files: list[Path]) -> None:
    for path in files:
        relative = path.relative_to(root).as_posix()
        lowered = relative.lower()
        if any(token in lowered for token in FORBIDDEN_NAMES):
            raise ValueError(f"forbidden release path: {relative}")
        if relative.startswith("portable_config/") and path.suffix.lower() in {".lua", ".conf"}:
            text = path.read_text(encoding="utf-8").lower()
            for token in FORBIDDEN_RUNTIME_CONTENT:
                if token in text:
                    raise ValueError(f"forbidden runtime content {token!r}: {relative}")


def write_zip(root: Path, output: Path, files: list[Path]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.unlink(missing_ok=True)
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            relative = path.relative_to(root).as_posix()
            info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o644 & 0xFFFF) << 16
            info.create_system = 3
            archive.writestr(info, path.read_bytes())
    temporary.replace(output)


def verify_zip(root: Path, output: Path, files: list[Path]) -> list[str]:
    expected = {path.relative_to(root).as_posix(): path.read_bytes() for path in files}
    with zipfile.ZipFile(output) as archive:
        archive.testzip()
        names = sorted(name for name in archive.namelist() if not name.endswith("/"))
        if names != sorted(expected):
            missing = sorted(set(expected) - set(names))
            extra = sorted(set(names) - set(expected))
            raise ValueError(f"ZIP manifest mismatch missing={missing} extra={extra}")
        for name, content in expected.items():
            if archive.read(name) != content:
                raise ValueError(f"ZIP byte mismatch: {name}")
    with tempfile.TemporaryDirectory(prefix="uosc-waveform-package-") as directory:
        with zipfile.ZipFile(output) as archive:
            archive.extractall(directory)
        extracted = Path(directory)
        for name, content in expected.items():
            if (extracted / name).read_bytes() != content:
                raise ValueError(f"extracted byte mismatch: {name}")
    return sorted(expected)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--sha-output", type=Path)
    parser.add_argument("--verification-output", type=Path)
    args = parser.parse_args()

    root = args.root.resolve()
    detected = runtime_version(root)
    version = args.version or detected
    if version != detected:
        raise ValueError(f"requested version {version!r} does not match runtime {detected!r}")
    output = (args.output or root / "dist" / f"uosc-waveform-{version}.zip").resolve()
    sha_output = (args.sha_output or output.with_name(output.stem + "-SHA256.txt")).resolve()
    verification_output = (args.verification_output or output.with_name(output.stem + "-verification.txt")).resolve()

    files = selected_files(root)
    verify_source(root, files)
    write_zip(root, output, files)
    manifest = verify_zip(root, output, files)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    sha_output.write_text(f"{digest}  {output.name}\n", encoding="utf-8")
    verification_output.write_text(
        "\n".join([
            f"uosc-waveform {version} reproducible package verification",
            f"zip={output.name}",
            f"sha256={digest}",
            f"files={len(manifest)}",
            "zip_integrity=PASS",
            "source_to_zip_bytes=PASS",
            "forbidden_runtime_artifacts=PASS",
            "manifest:",
            *manifest,
            "",
        ]),
        encoding="utf-8",
    )
    print(output)
    print(f"sha256={digest}")
    print(f"files={len(manifest)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
