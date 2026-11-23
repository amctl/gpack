#!/usr/bin/env python3
"""Run the paired H3 indexed runtime lookup comparison."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import pathlib
import platform
import re
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = pathlib.Path(__file__).resolve().parent
H2_PATH = HERE.parent / "h2-frame-granularity" / "harness.py"
spec = importlib.util.spec_from_file_location("h2_harness", H2_PATH)
h2 = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(h2)
METRIC = re.compile(r"H3RUNTIME (\S+) (\d+) (\d+) ([\d.eE+-]+) ([\d.eE+-]+) ([\d.eE+-]+) ([\d.eE+-]+) ([\d.eE+-]+) (\d+)")


def manifest(root: pathlib.Path, out: pathlib.Path) -> int:
    rows = []
    for path in h2.regular_files(root):
        rel = path.relative_to(root).as_posix()
        rows.append((rel.encode("utf-8"), zlib.crc32(path.read_bytes()) & 0xffffffff))
    rows.sort(key=lambda row: row[0])
    out.write_bytes(b"".join(path + b"\t" + str(crc).encode() + b"\n" for path, crc in rows))
    return len(rows)


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, capture_output=True, text=True, check=False)


def validate(binary: pathlib.Path, archive: pathlib.Path, hashes: pathlib.Path) -> bool:
    return run([str(binary), str(archive), str(hashes), "validate"]).returncode == 0


def malformed(binary: pathlib.Path, archive: pathlib.Path, hashes: pathlib.Path,
              scratch: pathlib.Path) -> dict[str, bool]:
    data = bytearray(archive.read_bytes())
    magic, version, layout, count, index_offset = h2.HEADER.unpack_from(data)
    first = index_offset + h2.INDEX_COUNT.size
    path_len, _, segments = h2.FILE_PREFIX.unpack_from(data, first)
    segment_at = first + h2.FILE_PREFIX.size + path_len
    payload_at, compressed, _ = h2.SEGMENT.unpack_from(data, segment_at)
    cases = {
        "truncated_index": data[:-1],
        "out_of_range_offset": bytearray(data),
        "unsafe_path": bytearray(data),
        "invalid_frame": bytearray(data),
    }
    struct.pack_into("<Q", cases["out_of_range_offset"], segment_at, index_offset + 1)
    path_at = first + h2.FILE_PREFIX.size
    if path_len < 3:
        raise ValueError("cannot form unsafe path fixture")
    cases["unsafe_path"][path_at:path_at + 3] = b"../"
    cases["invalid_frame"][payload_at] ^= 0xff
    outcomes = {}
    for name, payload in cases.items():
        bad = scratch / f"bad-{name}.gpkh2"
        bad.write_bytes(payload)
        result = run([str(binary), str(bad), str(hashes), "validate"] if name != "invalid_frame"
                     else [str(binary), str(bad), str(hashes)])
        outcomes[name] = result.returncode != 0
    return outcomes


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: bench.py CORPUS_ROOT GOOSE_BINARY C_BINARY")
    real_root, goose_bin, c_bin = map(lambda x: pathlib.Path(x).resolve(), sys.argv[1:])
    if not real_root.is_dir():
        raise SystemExit(f"corpus directory not found: {real_root}")
    for binary in (goose_bin, c_bin):
        if not binary.is_file():
            raise SystemExit(f"reader binary not found: {binary}")
    output = HERE / "results.json"
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="gpack-h3-bench-"))
    try:
        workloads = h2.create_inputs(scratch / "inputs", real_root)
        observations = []
        summaries = {}
        malformed_results = {}
        archive_hashes = {}
        for name in ("godot-real", "mixed"):
            root = workloads[name]
            archive = scratch / f"{name}.gpkh2"
            hashes = scratch / f"{name}.crc.tsv"
            count = manifest(root, hashes)
            packed = h2.pack_archive(root, archive, "per-asset", None)
            source_check = h2.lookup_archive(archive, root)
            if not source_check["all_assets_match_source"]:
                raise RuntimeError(f"H2 source verification failed for {name}")
            if not validate(goose_bin, archive, hashes) or not validate(c_bin, archive, hashes):
                raise RuntimeError(f"reader archive preflight failed for {name}")
            archive_hashes[name] = packed["archive_sha256"]
            if name == "godot-real":
                for label, binary in (("goose", goose_bin), ("c-reference", c_bin)):
                    malformed_results[label] = malformed(binary, archive, hashes, scratch)
            rows = []
            for paired_run in range(5):
                order = (("goose", goose_bin), ("c-reference", c_bin))
                if paired_run % 2:
                    order = tuple(reversed(order))
                for label, binary in order:
                    timed = run(["/usr/bin/time", "-f", "GPACK_H3_RSS_KIB=%M", str(binary), str(archive), str(hashes)])
                    match = METRIC.search(timed.stdout)
                    rss = re.search(r"GPACK_H3_RSS_KIB=(\d+)", timed.stderr)
                    if timed.returncode or not match or not rss:
                        raise RuntimeError(f"{label} failed on {name}: {timed.stderr[-1200:]} {timed.stdout[-500:]}")
                    _, files, byte_count, parse_s, runtime_s, mib_s, p50, p95, working = match.groups()
                    row = {"workload": name, "paired_run": paired_run + 1, "reader": label,
                           "files": int(files), "bytes": int(byte_count), "parse_seconds": float(parse_s),
                           "lookup_seconds": float(runtime_s), "mib_s": float(mib_s),
                           "p50_ms": float(p50), "p95_ms": float(p95),
                           "max_asset_working_bytes": int(working), "peak_rss_kib": int(rss.group(1))}
                    if row["files"] != count or row["bytes"] != source_check["bytes_read"]:
                        raise RuntimeError(f"{label} result count/bytes mismatch for {name}")
                    rows.append(row)
                    observations.append(row)
            summaries[name] = {}
            for label in ("goose", "c-reference"):
                selected = [row for row in rows if row["reader"] == label]
                summaries[name][label] = {
                    key: {"median": statistics.median(row[key] for row in selected),
                          "min": min(row[key] for row in selected), "max": max(row[key] for row in selected)}
                    for key in ("parse_seconds", "lookup_seconds", "mib_s", "p50_ms", "p95_ms", "peak_rss_kib")
                }
            archive.unlink()
        st = os.statvfs("/tmp")
        cpu = next((line.split(":", 1)[1].strip() for line in pathlib.Path("/proc/cpuinfo").read_text().splitlines()
                    if line.startswith("model name")), platform.processor())
        payload = {
            "experiment": "H3 native-backed indexed runtime lookup", "date": "2026-11-23",
            "corpus_root": str(real_root), "h2_archive_version": h2.VERSION,
            "zstd_version": int(h2.zstd.ZSTD_versionNumber()), "reader_threads": 4,
            "paired_runs": 5, "archive_sha256": archive_hashes,
            "machine": {"os": platform.platform(), "cpu": cpu,
                        "ram_bytes": os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES"),
                        "tmp_free_bytes": st.f_bavail * st.f_frsize,
                        "cc": subprocess.run(["cc", "--version"], capture_output=True, text=True).stdout.splitlines()[0]},
            "malformed_rejection": malformed_results,
            "workloads": summaries, "observations": observations,
        }
        output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"results": str(output), "summaries": summaries,
                          "malformed_rejection": malformed_results}, indent=2))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()
