#!/usr/bin/env python3
"""Paired product v1 runtime benchmark. See protocol.md for build inputs."""
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
import subprocess
import sys
import tempfile
import zlib
from datetime import datetime
from zoneinfo import ZoneInfo

HERE = pathlib.Path(__file__).resolve().parent
H2 = HERE.parent / "h2-frame-granularity" / "harness.py"
spec = importlib.util.spec_from_file_location("h2", H2)
h2 = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(h2)
METRIC = re.compile(r"GPKV1 (\S+) (\d+) (\d+) (\d+) (\d+) ([\d.eE+-]+) ([\d.eE+-]+) ([\d.eE+-]+)")


def run(args: list[str], *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, check=False, env=env)


def manifest(root: pathlib.Path, out: pathlib.Path) -> tuple[int, int]:
    rows = []
    total = 0
    for path in h2.regular_files(root):
        rel = path.relative_to(root).as_posix().encode("utf-8")
        data = path.read_bytes()
        rows.append((rel, zlib.crc32(data) & 0xffffffff))
        total += len(data)
    rows.sort(key=lambda x: x[0])
    out.write_bytes(b"".join(p + b"\t" + str(c).encode() + b"\n" for p, c in rows))
    return len(rows), total


def valid(binary: pathlib.Path, archive: pathlib.Path, manifest_path: pathlib.Path) -> bool:
    return run([str(binary), str(archive), str(manifest_path), "validate"]).returncode == 0


def malformed_checks(goose_bin: pathlib.Path, c_bin: pathlib.Path, archive: pathlib.Path,
                     manifest_path: pathlib.Path, scratch: pathlib.Path) -> dict[str, dict[str, bool]]:
    original = archive.read_bytes()
    cases = {"truncated_header": original[:31], "truncated_index": original[:-1]}
    index_offset = int.from_bytes(original[24:32], "little")
    damaged_index = bytearray(original)
    damaged_index[index_offset + 4] ^= 1
    cases["index_crc_mismatch"] = bytes(damaged_index)
    damaged_payload = bytearray(original)
    at = index_offset + 4
    count = int.from_bytes(original[index_offset:index_offset + 4], "little")
    found_frame = False
    for _ in range(count):
        path_len = int.from_bytes(original[at:at + 4], "little")
        codec = original[at + 4]
        payload_offset = int.from_bytes(original[at + 16:at + 24], "little")
        stored_size = int.from_bytes(original[at + 24:at + 32], "little")
        at += 40 + path_len
        if codec == 1 and stored_size:
            damaged_payload[payload_offset] ^= 0xff
            found_frame = True
            break
    if found_frame:
        cases["invalid_frame_or_payload_crc"] = bytes(damaged_payload)
    outcomes: dict[str, dict[str, bool]] = {"goose": {}, "c-reference": {}}
    for label, payload in cases.items():
        bad = scratch / f"malformed-{label}.gpk"
        bad.write_bytes(payload)
        for name, binary in (("goose", goose_bin), ("c-reference", c_bin)):
            command = [str(binary), str(bad), str(manifest_path)]
            if label != "invalid_frame_or_payload_crc":
                command.append("validate")
            proc = run(command)
            outcomes[name][label] = proc.returncode != 0
    return outcomes


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("usage: bench.py CORPUS_ROOT GPACK_CLI GOOSE_READER C_READER")
    corpus, packer, goose_bin, c_bin = map(lambda p: pathlib.Path(p).resolve(), sys.argv[1:])
    for path in (corpus, packer, goose_bin, c_bin):
        if not path.exists():
            raise SystemExit(f"missing benchmark input: {path}")
    env = os.environ.copy()
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="gpack-v1-runtime-"))
    try:
        inputs = h2.create_inputs(scratch / "inputs", corpus)
        records: list[dict] = []
        summaries = {}
        hashes = {}
        malformed = {}
        workload_meta = {}
        for workload in ("godot-real", "mixed"):
            root = inputs[workload]
            archive = scratch / f"{workload}.gpk"
            manifest_path = scratch / f"{workload}.crc.tsv"
            file_count, byte_count = manifest(root, manifest_path)
            packed = run([str(packer), "pack", str(root), str(archive)], env=env)
            if packed.returncode:
                raise RuntimeError(f"product pack failed for {workload}: {packed.stderr[-1500:]}")
            hashes[workload] = hashlib.sha256(archive.read_bytes()).hexdigest()
            workload_meta[workload] = {"files": file_count, "source_bytes": byte_count,
                                       "archive_bytes": archive.stat().st_size,
                                       "archive_sha256": hashes[workload]}
            if not valid(goose_bin, archive, manifest_path) or not valid(c_bin, archive, manifest_path):
                raise RuntimeError(f"reader preflight failed for {workload}")
            if workload == "godot-real":
                malformed = malformed_checks(goose_bin, c_bin, archive, manifest_path, scratch)
            workload_rows = []
            for pair in range(5):
                order = [("goose", goose_bin), ("c-reference", c_bin)]
                if pair % 2:
                    order.reverse()
                for label, binary in order:
                    proc = run(["/usr/bin/time", "-f", "GPACK_V1_RSS_KIB=%M",
                                str(binary), str(archive), str(manifest_path)], env=env)
                    metric = METRIC.search(proc.stdout)
                    rss = re.search(r"GPACK_V1_RSS_KIB=(\d+)", proc.stderr)
                    if proc.returncode or not metric or not rss:
                        raise RuntimeError(f"{label} failed: {proc.stderr[-1200:]} {proc.stdout[-500:]}")
                    got_label, files, nbytes, parse_ns, run_ns, mib_s, p50, p95 = metric.groups()
                    row = {"workload": workload, "paired_run": pair + 1, "reader": label,
                           "files": int(files), "bytes": int(nbytes), "parse_ns": int(parse_ns),
                           "lookup_ns": int(run_ns), "mib_s": float(mib_s),
                           "p50_ms": float(p50), "p95_ms": float(p95),
                           "peak_rss_kib": int(rss.group(1)), "execution_order": [x[0] for x in order]}
                    if got_label != label or row["files"] != file_count or row["bytes"] != byte_count:
                        raise RuntimeError(f"{label} count/source-byte mismatch for {workload}")
                    records.append(row)
                    workload_rows.append(row)
            summaries[workload] = {}
            for label in ("goose", "c-reference"):
                selected = [r for r in workload_rows if r["reader"] == label]
                summaries[workload][label] = {
                    key: {"median": statistics.median(r[key] for r in selected),
                          "min": min(r[key] for r in selected), "max": max(r[key] for r in selected)}
                    for key in ("parse_ns", "lookup_ns", "mib_s", "p50_ms", "p95_ms", "peak_rss_kib")}
            by_pair = {}
            for pair in range(1, 6):
                pair_rows = {r["reader"]: r for r in workload_rows if r["paired_run"] == pair}
                by_pair[str(pair)] = pair_rows["goose"]["mib_s"] / pair_rows["c-reference"]["mib_s"]
            summaries[workload]["paired_throughput_ratio_goose_over_c"] = {
                "median": statistics.median(by_pair.values()),
                "min": min(by_pair.values()), "max": max(by_pair.values()), "runs": by_pair}
            archive.unlink()
        cpu = next((line.split(":", 1)[1].strip() for line in pathlib.Path("/proc/cpuinfo").read_text().splitlines()
                    if line.startswith("model name")), platform.processor())
        output = {"experiment": "GPack product v1 runtime throughput",
                  "date": datetime.now(ZoneInfo("Asia/Kolkata")).date().isoformat(),
                  "corpus_root": str(corpus), "paired_runs": 5, "reader_threads": 4,
                  "reader_limit_bytes": 32 * 1024 * 1024,
                  "build_mode": os.environ.get("GPACK_BUILD_DESCRIPTION", "unspecified"),
                  "zstd_version_number": int(run([str(c_bin), "--version"]).stdout.strip()),
                  "machine": {"os": platform.platform(), "cpu": cpu,
                              "ram_bytes": os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES"),
                              "cc": run(["gcc", "--version"]).stdout.splitlines()[0]},
                  "workload_metadata": workload_meta, "malformed_rejection": malformed,
                  "summaries": summaries, "observations": records}
        destination = HERE / "results.json"
        destination.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"results": str(destination), "summaries": summaries,
                          "malformed_rejection": malformed}, indent=2))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()
