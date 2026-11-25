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


def test_cli() -> None:
    import json

    gpack_exe = BUILD / ("gpack.exe" if os.name == "nt" else "gpack")
    cli_dir = BUILD / "cli-test"
    if cli_dir.exists():
        shutil.rmtree(cli_dir)
    input_dir = cli_dir / "input"
    (input_dir / "sub").mkdir(parents=True)
    alpha_bytes = b"hello cli\n" * 64
    (input_dir / "alpha.txt").write_bytes(alpha_bytes)
    (input_dir / "sub" / "empty.bin").write_bytes(b"")
    archive = cli_dir / "out.gpk"

    help_res = subprocess.run([str(gpack_exe), "--help"], capture_output=True, text=True, check=True)
    if "Commands:" not in help_res.stdout or "verify" not in help_res.stdout:
        raise RuntimeError(f"unexpected --help output: {help_res.stdout!r}")
    subprocess.run([str(gpack_exe), "help", "verify"], capture_output=True, text=True, check=True)
    ver_res = subprocess.run([str(gpack_exe), "--version"], capture_output=True, text=True, check=True)
    if "gpack 1.0.0" not in ver_res.stdout or "zstd 1.5.7" not in ver_res.stdout:
        raise RuntimeError(f"unexpected --version output: {ver_res.stdout!r}")

    pack_res = subprocess.run([str(gpack_exe), "pack", "--json", str(input_dir), str(archive)], capture_output=True, text=True, check=True)
    pack_json = json.loads(pack_res.stdout)
    if not pack_json["ok"] or pack_json["entry_count"] != 2 or pack_json["empty_count"] != 1:
        raise RuntimeError(f"unexpected pack --json output: {pack_res.stdout!r}")

    listed = subprocess.run([str(gpack_exe), "list", str(archive)], capture_output=True, text=True, check=True)
    lines = listed.stdout.splitlines()
    if len(lines) != 2 or not lines[0].startswith("alpha.txt ") or lines[1] != "sub/empty.bin 0 0":
        raise RuntimeError(f"unexpected gpack list output: {listed.stdout!r}")

    list_long = subprocess.run([str(gpack_exe), "list", "--long", str(archive)], capture_output=True, text=True, check=True)
    if "CODEC" not in list_long.stdout or "alpha.txt" not in list_long.stdout:
        raise RuntimeError(f"unexpected list --long output: {list_long.stdout!r}")

    list_json_res = subprocess.run([str(gpack_exe), "list", "--json", str(archive)], capture_output=True, text=True, check=True)
    list_json = json.loads(list_json_res.stdout)
    if list_json["entry_count"] != 2 or len(list_json["entries"]) != 2:
        raise RuntimeError(f"unexpected list --json output: {list_json_res.stdout!r}")

    info_res = subprocess.run([str(gpack_exe), "info", "--json", str(archive)], capture_output=True, text=True, check=True)
    info_json = json.loads(info_res.stdout)
    if info_json["format"] != "1.0" or info_json["entry_count"] != 2:
        raise RuntimeError(f"unexpected info --json output: {info_res.stdout!r}")
    subprocess.run([str(gpack_exe), "info", str(archive)], capture_output=True, text=True, check=True)

    run([str(gpack_exe), "verify", str(archive)])
    verify_res = subprocess.run([str(gpack_exe), "verify", "--jobs=2", "--max-size=1M", "--json", str(archive)], capture_output=True, text=True, check=True)
    verify_json = json.loads(verify_res.stdout)
    if not verify_json["ok"] or verify_json["verified_entries"] != 2:
        raise RuntimeError(f"unexpected verify --json output: {verify_res.stdout!r}")

    read_res = subprocess.run([str(gpack_exe), "read", str(archive), "alpha.txt"], capture_output=True, check=True)
    if read_res.stdout != alpha_bytes:
        raise RuntimeError("gpack read returned mismatched bytes")
    read_missing = subprocess.run([str(gpack_exe), "read", str(archive), "missing.txt"], capture_output=True, text=True, check=False)
    if read_missing.returncode != 1:
        raise RuntimeError(f"expected read missing failure (1), got {read_missing.returncode}")
    read_cap = subprocess.run([str(gpack_exe), "read", "--max-size", "4", str(archive), "alpha.txt"], capture_output=True, text=True, check=False)
    if read_cap.returncode != 1:
        raise RuntimeError(f"expected read max-size failure (1), got {read_cap.returncode}")

    corrupt = cli_dir / "corrupt.gpk"
    data = bytearray(archive.read_bytes())
    data[64] ^= 0x01
    corrupt.write_bytes(data)
    bad_verify = subprocess.run([str(gpack_exe), "verify", str(corrupt)], capture_output=True, text=True, check=False)
    if bad_verify.returncode != 1 or "alpha.txt" not in bad_verify.stderr:
        raise RuntimeError(f"expected verify failure (1) naming alpha.txt, got rc={bad_verify.returncode} stderr={bad_verify.stderr!r}")

    bad_usage = subprocess.run([str(gpack_exe)], capture_output=True, text=True, check=False)
    if bad_usage.returncode != 2:
        raise RuntimeError(f"expected usage error (2), got {bad_usage.returncode}")
    bad_flag = subprocess.run([str(gpack_exe), "verify", "--nope", str(archive)], capture_output=True, text=True, check=False)
    if bad_flag.returncode != 2:
        raise RuntimeError(f"expected unknown-flag error (2), got {bad_flag.returncode}")

    if os.name != "nt":
        sym_dir = cli_dir / "sym-input"
        sym_dir.mkdir()
        (sym_dir / "real.txt").write_bytes(b"ok")
        os.symlink(sym_dir / "real.txt", sym_dir / "link.txt")
        sym_out = cli_dir / "sym.gpk"
        bad_pack = subprocess.run([str(gpack_exe), "pack", str(sym_dir), str(sym_out)], capture_output=True, text=True, check=False)
        if bad_pack.returncode != 1 or sym_out.exists():
            raise RuntimeError(f"expected symlink pack rejection, got rc={bad_pack.returncode}")
    shutil.rmtree(cli_dir)


def test() -> None:
    verify_notices()
    exe = BUILD / ("native_abi.exe" if os.name == "nt" else "native_abi")
    run([str(exe)])
    format_exe = BUILD / ("format_v1.exe" if os.name == "nt" else "format_v1")
    run([str(format_exe)])
    pack_exe = BUILD / ("pack_read.exe" if os.name == "nt" else "pack_read")
    run([str(pack_exe)])
    test_cli()


def ci() -> None:
    check()
    build()
    test()


def package() -> None:
    import hashlib
    import platform
    import tarfile
    import zipfile

    verify_notices()
    exe_name = "gpack.exe" if os.name == "nt" else "gpack"
    gpack_exe = BUILD / exe_name
    if not gpack_exe.is_file():
        raise RuntimeError(f"missing built CLI binary: {gpack_exe} (run 'build' or 'ci' first)")

    ver_out = subprocess.run([str(gpack_exe), "--version"], capture_output=True, text=True, check=True).stdout.strip()
    if not ver_out.startswith("gpack "):
        raise RuntimeError(f"unexpected --version output: {ver_out!r}")
    cli_version = ver_out.split()[1]

    tag = os.environ.get("GPACK_RELEASE_TAG", f"v{cli_version}")
    expected_version = tag.removeprefix("v").split("-", 1)[0]
    if cli_version != expected_version:
        raise RuntimeError(f"release tag {tag!r} does not match CLI version {cli_version!r}")

    os_label = "windows" if os.name == "nt" else ("macos" if sys.platform == "darwin" else "linux")
    machine = platform.machine().lower()
    arch_label = {"x86_64": "x64", "amd64": "x64", "arm64": "arm64", "aarch64": "arm64"}.get(machine, machine)
    target = os.environ.get("GPACK_RELEASE_TARGET", f"{os_label}-{arch_label}")

    bundle_name = f"gpack-{tag}-{target}"
    dist_dir = BUILD / "dist"
    stage_dir = dist_dir / bundle_name
    if stage_dir.exists():
        shutil.rmtree(stage_dir)
    notices_dst = stage_dir / "THIRD_PARTY_NOTICES"
    notices_dst.mkdir(parents=True)
    shutil.copy2(gpack_exe, stage_dir / exe_name)
    shutil.copyfile(ROOT / "LICENSE", stage_dir / "LICENSE")
    shutil.copyfile(BUILD / "THIRD_PARTY_NOTICES" / "ZSTD-LICENSE", notices_dst / "ZSTD-LICENSE")
    shutil.copyfile(BUILD / "THIRD_PARTY_NOTICES" / "ZSTD-COPYING", notices_dst / "ZSTD-COPYING")

    if os.name == "nt":
        archive_path = dist_dir / f"{bundle_name}.zip"
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for item in sorted(stage_dir.rglob("*")):
                if item.is_file():
                    zf.write(item, f"{bundle_name}/{item.relative_to(stage_dir).as_posix()}")
    else:
        archive_path = dist_dir / f"{bundle_name}.tar.gz"
        with tarfile.open(archive_path, "w:gz") as tf:
            for item in sorted(stage_dir.rglob("*")):
                if item.is_file():
                    tf.add(item, arcname=f"{bundle_name}/{item.relative_to(stage_dir).as_posix()}")

    digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    (dist_dir / f"{archive_path.name}.sha256").write_text(f"{digest}  {archive_path.name}\n", encoding="utf-8")
    shutil.rmtree(stage_dir)
    print(f"packaged {archive_path} (sha256={digest})")


COMMANDS = {"format": format_sources, "check": check, "build": build, "test": test, "ci": ci, "package": package}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        raise SystemExit(f"usage: {pathlib.Path(sys.argv[0]).name} {{{','.join(COMMANDS)}}}")
    COMMANDS[sys.argv[1]]()
