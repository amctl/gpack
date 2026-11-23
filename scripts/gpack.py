#!/usr/bin/env python3
"""Provider-neutral build and validation entrypoints for gpack."""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
GOOSE = os.environ.get("GOOSE", "goose")
BUILD = ROOT / "build"


def run(args: list[str], *, cwd: pathlib.Path = ROOT) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def goose(*args: str) -> None:
    run([GOOSE, *args])


def format_sources() -> None:
    goose("format", "cmd", "src/gpack", "tests")


def check() -> None:
    goose("format", "--check", "cmd", "src/gpack", "tests")
    goose("check", "cmd/gpack.goose")
    goose("check", "tests/native_abi.goose")
    goose("check", "tests/format_v1.goose")
    goose("check", "tests/pack_read.goose")


def build() -> None:
    BUILD.mkdir(exist_ok=True)
    goose("build", "cmd/gpack.goose", "-o", str(BUILD / ("gpack.exe" if os.name == "nt" else "gpack")))
    goose("build", "tests/native_abi.goose", "-o", str(BUILD / ("native_abi.exe" if os.name == "nt" else "native_abi")))
    goose("build", "tests/format_v1.goose", "-o", str(BUILD / ("format_v1.exe" if os.name == "nt" else "format_v1")))
    goose("build", "tests/pack_read.goose", "-o", str(BUILD / ("pack_read.exe" if os.name == "nt" else "pack_read")))
    verify_static_zstd()
    notices = BUILD / "THIRD_PARTY_NOTICES"
    notices.mkdir(exist_ok=True)
    shutil.copyfile(ROOT / "third_party/zstd-1.5.7/LICENSE", notices / "ZSTD-LICENSE")
    shutil.copyfile(ROOT / "third_party/zstd-1.5.7/COPYING", notices / "ZSTD-COPYING")


def verify_notices() -> None:
    notices = BUILD / "THIRD_PARTY_NOTICES"
    for source, name in (("LICENSE", "ZSTD-LICENSE"), ("COPYING", "ZSTD-COPYING")):
        expected = (ROOT / "third_party/zstd-1.5.7" / source).read_bytes()
        actual_path = notices / name
        if not actual_path.is_file() or actual_path.read_bytes() != expected:
            raise RuntimeError(f"missing or changed third-party notice: {actual_path}")


def verify_static_zstd() -> None:
    executables = [
        BUILD / (name + (".exe" if os.name == "nt" else ""))
        for name in ("gpack", "native_abi", "format_v1", "pack_read")
    ]
    if os.name == "nt":
        command = shutil.which("dumpbin")
        if command is None:
            compiler = shutil.which("cl")
            if compiler is not None:
                sibling = pathlib.Path(compiler).with_name("dumpbin.exe")
                if sibling.is_file():
                    command = str(sibling)
        if command is None:
            raise RuntimeError("cannot verify static Zstandard linkage: dumpbin is unavailable")
        args = lambda exe: [command, "/DEPENDENTS", str(exe)]
    elif sys.platform == "darwin":
        command = "otool"
        args = lambda exe: [command, "-L", str(exe)]
    else:
        command = "ldd"
        args = lambda exe: [command, str(exe)]
    if os.name != "nt" and shutil.which(command) is None:
        raise RuntimeError(f"cannot verify static Zstandard linkage: {command} is unavailable")
    for executable in executables:
        result = subprocess.run(args(executable), capture_output=True, text=True, check=False)
        if result.returncode != 0 or "zstd" in (result.stdout + result.stderr).lower():
            raise RuntimeError(f"unexpected dynamic Zstandard dependency in {executable}: {result.stdout} {result.stderr}")


def test() -> None:
    verify_notices()
    exe = BUILD / ("native_abi.exe" if os.name == "nt" else "native_abi")
    run([str(exe)])
    format_exe = BUILD / ("format_v1.exe" if os.name == "nt" else "format_v1")
    run([str(format_exe)])
    pack_exe = BUILD / ("pack_read.exe" if os.name == "nt" else "pack_read")
    run([str(pack_exe)])


def ci() -> None:
    check()
    build()
    test()


COMMANDS = {"format": format_sources, "check": check, "build": build, "test": test, "ci": ci}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        raise SystemExit(f"usage: {pathlib.Path(sys.argv[0]).name} {{{','.join(COMMANDS)}}}")
    COMMANDS[sys.argv[1]]()
