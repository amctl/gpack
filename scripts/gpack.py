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
    goose("build", "--stack-reserve", "16G", "cmd/gpack.goose", "-o", str(BUILD / ("gpack.exe" if os.name == "nt" else "gpack")))
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
    if "gpack 1.1.0" not in ver_res.stdout or "zstd 1.5.7" not in ver_res.stdout:
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

    help_help = subprocess.run([str(gpack_exe), "help", "--help"], capture_output=True, text=True, check=False)
    if help_help.returncode != 0 or "Usage: gpack help" not in help_help.stdout:
        raise RuntimeError(f"expected help --help success, got rc={help_help.returncode} out={help_help.stdout!r}")
    help_extra = subprocess.run([str(gpack_exe), "help", "pack", "extra"], capture_output=True, text=True, check=False)
    if help_extra.returncode != 2 or "unknown help topic" in help_extra.stderr:
        raise RuntimeError(f"expected extra-arg help error, got rc={help_extra.returncode} stderr={help_extra.stderr!r}")

    for args in (
        ["pack", "--json", str(cli_dir / "missing_dir"), str(cli_dir / "missing.gpk")],
        ["list", "--json", str(cli_dir / "missing.gpk")],
        ["info", "--json", str(cli_dir / "missing.gpk")],
        ["verify", "--json", str(corrupt)],
    ):
        err_res = subprocess.run([str(gpack_exe), *args], capture_output=True, text=True, check=False)
        if err_res.returncode != 1:
            raise RuntimeError(f"expected exit 1 for {args}, got {err_res.returncode}")
        err_json = json.loads(err_res.stdout)
        if err_json.get("ok") is not False or not err_json.get("error"):
            raise RuntimeError(f"unexpected --json error payload for {args}: {err_res.stdout!r}")
    verify_err_json = json.loads(
        subprocess.run([str(gpack_exe), "verify", "--json", str(corrupt)], capture_output=True, text=True, check=False).stdout
    )
    if verify_err_json.get("failed_path") != "alpha.txt":
        raise RuntimeError(f"expected failed_path='alpha.txt' in verify --json error: {verify_err_json!r}")

    dash_dir = cli_dir / "dash-input"
    dash_dir.mkdir()
    (dash_dir / "-dash.txt").write_bytes(b"dash payload")
    dash_gpk = cli_dir / "dash.gpk"
    subprocess.run([str(gpack_exe), "pack", str(dash_dir), str(dash_gpk)], capture_output=True, text=True, check=True)
    ls_res = subprocess.run([str(gpack_exe), "ls", str(dash_gpk)], capture_output=True, text=True, check=True)
    if not ls_res.stdout.startswith("-dash.txt "):
        raise RuntimeError(f"unexpected ls output: {ls_res.stdout!r}")
    cat_res = subprocess.run([str(gpack_exe), "cat", "--", str(dash_gpk), "-dash.txt"], capture_output=True, check=True)
    if cat_res.stdout != b"dash payload":
        raise RuntimeError("cat -- -dash.txt returned mismatched bytes")

    if os.name != "nt":
        sym_dir = cli_dir / "sym-input"
        sym_dir.mkdir()
        (sym_dir / "real.txt").write_bytes(b"ok")
        os.symlink(sym_dir / "real.txt", sym_dir / "link.txt")
        sym_out = cli_dir / "sym.gpk"
        bad_pack = subprocess.run([str(gpack_exe), "pack", str(sym_dir), str(sym_out)], capture_output=True, text=True, check=False)
        if bad_pack.returncode != 1 or sym_out.exists():
            raise RuntimeError(f"expected symlink pack rejection, got rc={bad_pack.returncode}")

    # Verify and read >2 GiB raw assets (guards against 32-bit pread/INT_MAX/stack-reserve limits).
    import struct
    import zlib

    large_size = 0x80001000
    large_crc = 0
    zero_chunk = b"\x00" * (1024 * 1024)
    remaining = large_size
    while remaining > 0:
        n = min(remaining, len(zero_chunk))
        large_crc = zlib.crc32(zero_chunk[:n], large_crc)
        remaining -= n
    large_crc &= 0xFFFFFFFF
    large_name = b"large_raw.bin"
    large_index_offset = 64 + large_size
    large_index = bytearray(struct.pack("<I", 1))
    large_index += struct.pack("<IB3BQQQII", len(large_name), 0, 0, 0, 0, large_size, 64, large_size, large_crc, 0)
    large_index += large_name
    large_index_crc = zlib.crc32(large_index) & 0xFFFFFFFF
    large_hdr = bytearray(64)
    large_hdr[0:8] = b"GPKARCH\0"
    struct.pack_into("<HHIQQQI", large_hdr, 8, 1, 0, 64, 1, large_index_offset, len(large_index), large_index_crc)
    struct.pack_into("<I", large_hdr, 44, zlib.crc32(large_hdr) & 0xFFFFFFFF)
    large_gpk = cli_dir / "large_raw.gpk"
    with open(large_gpk, "wb") as f:
        f.write(large_hdr)
        f.seek(large_index_offset)
        f.write(large_index)

    large_verify = subprocess.run([str(gpack_exe), "verify", "-j", "2", "-m", "4G", str(large_gpk)], capture_output=True, text=True, check=False)
    if large_verify.returncode != 0:
        raise RuntimeError(f"expected >2 GiB raw verify to pass, got rc={large_verify.returncode}: {large_verify.stderr}")
    proc = subprocess.Popen([str(gpack_exe), "read", "-m", "4G", str(large_gpk), "large_raw.bin"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert proc.stdout is not None
    read_total = 0
    while True:
        chunk = proc.stdout.read(1024 * 1024)
        if not chunk:
            break
        read_total += len(chunk)
    _, stderr_bytes = proc.communicate()
    if proc.returncode != 0 or read_total != large_size:
        raise RuntimeError(f"expected >2 GiB raw read to write {large_size} bytes, got rc={proc.returncode} size={read_total} stderr={stderr_bytes!r}")

    # Verify and read >2 GiB streaming Zstandard asset (stored_size > 1 MiB, uncompressed > INT_MAX).
    zstd_src = cli_dir / "large-zstd-src"
    zstd_src.mkdir()
    rng_state = 0x12345678
    prefix = bytearray(1258291)
    for idx in range(len(prefix)):
        rng_state = (rng_state * 1664525 + 1013904223) & 0xFFFFFFFF
        prefix[idx] = (rng_state >> 24) & 0xFF
    large_zstd_input = zstd_src / "large_zstd.bin"
    large_zstd_size = len(prefix) + 0x80000000
    with open(large_zstd_input, "wb") as f:
        f.write(prefix)
        f.truncate(large_zstd_size)
    large_zstd_gpk = cli_dir / "large_zstd.gpk"
    subprocess.run([str(gpack_exe), "pack", str(zstd_src), str(large_zstd_gpk)], capture_output=True, text=True, check=True)
    zstd_list = json.loads(subprocess.run([str(gpack_exe), "list", "--json", str(large_zstd_gpk)], capture_output=True, text=True, check=True).stdout)
    zstd_entry = zstd_list["entries"][0]
    if zstd_entry["codec"] != "zstd" or zstd_entry["stored_size"] <= 1024 * 1024:
        raise RuntimeError(f"expected streaming zstd >1 MiB entry, got {zstd_entry!r}")
    large_zstd_verify = subprocess.run([str(gpack_exe), "verify", "-j", "2", "-m", "4G", str(large_zstd_gpk)], capture_output=True, text=True, check=False)
    if large_zstd_verify.returncode != 0:
        raise RuntimeError(f"expected >2 GiB zstd verify to pass, got rc={large_zstd_verify.returncode}: {large_zstd_verify.stderr}")
    zproc = subprocess.Popen([str(gpack_exe), "read", "-m", "4G", str(large_zstd_gpk), "large_zstd.bin"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert zproc.stdout is not None
    zread_total = 0
    zread_head = bytearray()
    while True:
        chunk = zproc.stdout.read(1024 * 1024)
        if not chunk:
            break
        if len(zread_head) < len(prefix):
            need = len(prefix) - len(zread_head)
            zread_head.extend(chunk[:need])
        zread_total += len(chunk)
    _, zstderr_bytes = zproc.communicate()
    if zproc.returncode != 0 or zread_total != large_zstd_size or zread_head != prefix:
        raise RuntimeError(f"expected >2 GiB zstd read to match {large_zstd_size} bytes, got rc={zproc.returncode} size={zread_total} stderr={zstderr_bytes!r}")
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

    dist_dir = BUILD / "dist"
    if dist_dir.exists():
        shutil.rmtree(dist_dir)
    dist_dir.mkdir(parents=True)

    standalone_name = f"gpack-{target}.exe" if os.name == "nt" else f"gpack-{target}"
    standalone_path = dist_dir / standalone_name
    shutil.copy2(gpack_exe, standalone_path)
    if os.name != "nt":
        strip_cmd = shutil.which("strip")
        if strip_cmd is not None:
            strip_args = [strip_cmd, "-x", str(standalone_path)] if sys.platform == "darwin" else [strip_cmd, str(standalone_path)]
            subprocess.run(strip_args, check=False)
        standalone_path.chmod(0o755)
    subprocess.run([str(standalone_path), "--version"], capture_output=True, text=True, check=True)

    standalone_digest = hashlib.sha256(standalone_path.read_bytes()).hexdigest()
    (dist_dir / f"{standalone_name}.sha256").write_text(f"{standalone_digest}  {standalone_name}\n", encoding="utf-8")

    bundle_name = f"gpack-{tag}-{target}"
    stage_dir = dist_dir / bundle_name
    bin_dir = stage_dir / "bin"
    notices_dst = stage_dir / "THIRD_PARTY_NOTICES"
    bin_dir.mkdir(parents=True)
    notices_dst.mkdir(parents=True)
    shutil.copy2(standalone_path, bin_dir / exe_name)
    shutil.copyfile(ROOT / "README.md", stage_dir / "README.md")
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
                    rel = item.relative_to(stage_dir).as_posix()
                    info = tf.gettarinfo(str(item), arcname=f"{bundle_name}/{rel}")
                    info.mode = 0o755 if rel == f"bin/{exe_name}" else 0o644
                    with item.open("rb") as fh:
                        tf.addfile(info, fh)

    digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    (dist_dir / f"{archive_path.name}.sha256").write_text(f"{digest}  {archive_path.name}\n", encoding="utf-8")
    shutil.rmtree(stage_dir)
    print(f"packaged {standalone_path} (sha256={standalone_digest})")
    print(f"packaged {archive_path} (sha256={digest})")


COMMANDS = {"format": format_sources, "check": check, "build": build, "test": test, "ci": ci, "package": package}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        raise SystemExit(f"usage: {pathlib.Path(sys.argv[0]).name} {{{','.join(COMMANDS)}}}")
    COMMANDS[sys.argv[1]]()
