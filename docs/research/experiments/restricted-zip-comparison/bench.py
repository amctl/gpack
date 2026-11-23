#!/usr/bin/env python3
"""Correctness-gated paired GPack/ZIP benchmark. See protocol.md."""
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
import time
import zlib
from datetime import datetime
from zoneinfo import ZoneInfo

HERE = pathlib.Path(__file__).resolve().parent
H2 = HERE.parent / "h2-frame-granularity" / "harness.py"
spec = importlib.util.spec_from_file_location("h2", H2)
h2 = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(h2)
GPK_METRIC = re.compile(r"GPKV1 goose (\d+) (\d+) (\d+) (\d+) ([\d.eE+-]+) ([\d.eE+-]+) ([\d.eE+-]+)")
ZIP_METRIC = re.compile(r"ZIPV1 goose (\d+) (\d+) (\d+) (\d+) ([\d.eE+-]+) ([\d.eE+-]+) ([\d.eE+-]+)")
RSS = re.compile(r"GPACK_V1_RSS_KIB=(\d+)")


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, check=False)


def manifest(root: pathlib.Path, out: pathlib.Path) -> tuple[int, int]:
    rows = []
    total = 0
    for path in h2.regular_files(root):
        rel = path.relative_to(root).as_posix().encode("utf-8")
        data = path.read_bytes()
        rows.append((rel, zlib.crc32(data) & 0xffffffff))
        total += len(data)
    rows.sort()
    out.write_bytes(b"".join(path + b"\t" + str(crc).encode() + b"\n" for path, crc in rows))
    return len(rows), total


def require_ok(command: list[str], label: str) -> str:
    proc = run(command)
    if proc.returncode:
        raise RuntimeError(f"{label}: {proc.stderr[-1200:]} {proc.stdout[-500:]}")
    return proc.stdout.strip()


def validate(binary: pathlib.Path, archive: pathlib.Path, source_manifest: pathlib.Path) -> None:
    require_ok([str(binary), str(archive), str(source_manifest), "validate"], f"validation failed: {archive}")


def zip_malformed_checks(reader: pathlib.Path, zpack: pathlib.Path, archive: pathlib.Path,
                         source_manifest: pathlib.Path, scratch: pathlib.Path) -> dict[str, bool]:
    original = archive.read_bytes()
    # The first local record starts at byte zero; its name length is at 26.
    name_len = int.from_bytes(original[26:28], "little")
    payload_offset = 30 + name_len
    eocd_at = original.rfind(b"PK\x05\x06")
    cd_offset = int.from_bytes(original[eocd_at + 16:eocd_at + 20], "little")
    first_cd_name_len = int.from_bytes(original[cd_offset + 28:cd_offset + 30], "little")
    descriptor_offset = payload_offset + int.from_bytes(original[cd_offset + 20:cd_offset + 24], "little")
    first_name = original[30:30 + name_len]
    slash = first_name.find(b"/")
    if slash < 0:
        raise RuntimeError("first ZIP path needs a separator for backslash/NUL fixtures")
    backslash = bytearray(original)
    backslash[30 + slash] = ord("\\")
    backslash[cd_offset + 46 + slash] = ord("\\")
    nul_name = bytearray(original)
    nul_name[30 + slash] = 0
    nul_name[cd_offset + 46 + slash] = 0
    malformed_cd = bytearray(original)
    malformed_cd[cd_offset] ^= 0xff
    bad_local_ref = bytearray(original)
    bad_local_ref[cd_offset + 42:cd_offset + 46] = (1).to_bytes(4, "little")
    out_of_range = bytearray(original)
    out_of_range[cd_offset + 42:cd_offset + 46] = (0xfffffffe).to_bytes(4, "little")
    bad_size = bytearray(original)
    old_uncompressed = int.from_bytes(original[cd_offset + 24:cd_offset + 28], "little")
    bad_size[cd_offset + 24:cd_offset + 28] = (old_uncompressed + 1).to_bytes(4, "little")
    zip64_compressed_size = bytearray(original)
    zip64_compressed_size[cd_offset + 20:cd_offset + 24] = b"\xff\xff\xff\xff"
    zip64_local_offset = bytearray(original)
    zip64_local_offset[cd_offset + 42:cd_offset + 46] = b"\xff\xff\xff\xff"
    zip64_entry_count = bytearray(original)
    zip64_entry_count[eocd_at + 8:eocd_at + 12] = b"\xff\xff\xff\xff"
    zip64_directory_size = bytearray(original)
    zip64_directory_size[eocd_at + 12:eocd_at + 16] = b"\xff\xff\xff\xff"
    zip64_directory_offset = bytearray(original)
    zip64_directory_offset[eocd_at + 16:eocd_at + 20] = b"\xff\xff\xff\xff"
    cases: dict[str, bytes] = {
        "truncated_eocd": original[:-1],
        "truncated_central_directory": original[:eocd_at - 1] + original[eocd_at:],
        "malformed_central_directory_signature": bytes(malformed_cd),
        "unsupported_method": original[:cd_offset + 10] + b"\x63\x00" + original[cd_offset + 12:],
        "zip64_uncompressed_size": original[:cd_offset + 24] + b"\xff\xff\xff\xff" + original[cd_offset + 28:],
        "zip64_compressed_size": bytes(zip64_compressed_size),
        "zip64_local_header_offset": bytes(zip64_local_offset),
        "zip64_entry_count": bytes(zip64_entry_count),
        "zip64_directory_size": bytes(zip64_directory_size),
        "zip64_directory_offset": bytes(zip64_directory_offset),
        "backslash_path": bytes(backslash),
        "nul_path": bytes(nul_name),
        "invalid_local_header_reference": bytes(bad_local_ref),
        "out_of_range_local_header_reference": bytes(out_of_range),
        "central_local_size_mismatch": bytes(bad_size),
    }
    unsafe = bytearray(original)
    unsafe[30] = ord("/")
    unsafe[cd_offset + 46] = ord("/")
    if name_len != first_cd_name_len:
        raise RuntimeError("ZIP local and central path lengths differ in fixture source")
    cases["absolute_path"] = bytes(unsafe)
    bad_descriptor = bytearray(original)
    bad_descriptor[descriptor_offset + 4] ^= 1
    cases["descriptor_crc_mismatch"] = bytes(bad_descriptor)
    damaged = bytearray(original)
    if payload_offset < cd_offset:
        damaged[payload_offset] ^= 0xff
        cases["payload_crc_or_deflate_corruption"] = bytes(damaged)
    overlap_root = scratch / "overlap-source"
    overlap_root.mkdir()
    (overlap_root / "a.bin").write_bytes(b"a" * 4096)
    (overlap_root / "b.bin").write_bytes(b"b")
    overlap_archive = scratch / "overlap-source.zip"
    require_ok([str(zpack), "STORE", str(overlap_root), str(overlap_archive)], "overlap fixture packing failed")
    overlap_bytes = overlap_archive.read_bytes()
    overlap_eocd = overlap_bytes.rfind(b"PK\x05\x06")
    overlap_cd = int.from_bytes(overlap_bytes[overlap_eocd + 16:overlap_eocd + 20], "little")
    first_cd = overlap_cd
    first_nlen = int.from_bytes(overlap_bytes[first_cd + 28:first_cd + 30], "little")
    first_elen = int.from_bytes(overlap_bytes[first_cd + 30:first_cd + 32], "little")
    first_clen = int.from_bytes(overlap_bytes[first_cd + 32:first_cd + 34], "little")
    second_cd = first_cd + 46 + first_nlen + first_elen + first_clen
    first_local = int.from_bytes(overlap_bytes[first_cd + 42:first_cd + 46], "little")
    second_local = int.from_bytes(overlap_bytes[second_cd + 42:second_cd + 46], "little")
    injection = first_local + 30 + int.from_bytes(overlap_bytes[first_local + 26:first_local + 28], "little") + 64
    segment = overlap_bytes[second_local:overlap_cd]
    if injection + len(segment) >= second_local:
        raise RuntimeError("overlap fixture segment does not fit inside first payload")
    overlapping = bytearray(overlap_bytes)
    overlapping[injection:injection + len(segment)] = segment
    overlapping[second_cd + 42:second_cd + 46] = injection.to_bytes(4, "little")
    cases["overlapping_payload_ranges"] = bytes(overlapping)
    results = {}
    for name, payload in cases.items():
        bad = scratch / f"malformed-{name}.zip"
        bad.write_bytes(payload)
        results[name] = run([str(reader), str(bad), str(source_manifest), "validate"]).returncode != 0
        if not results[name]:
            raise RuntimeError(f"ZIP reader accepted malformed fixture: {name}")
    return results


def edge_case_checks(gpack: pathlib.Path, raw_packer: pathlib.Path, greader: pathlib.Path,
                     zpack: pathlib.Path, zreader: pathlib.Path, scratch: pathlib.Path) -> dict:
    root = scratch / "zip-edge-cases"
    payloads = {"Case.txt": b"upper", "case.txt": b"lower", "empty.bin": b"",
                "caf\u00e9.txt": b"utf-8 path", "a/b": b"nested"}
    for name, content in payloads.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    source_manifest = scratch / "zip-edge-cases.crc.tsv"
    count, byte_count = manifest(root, source_manifest)
    gpk = scratch / "zip-edge-cases.gpk"
    require_ok([str(gpack), "pack", str(root), str(gpk)], "edge-case GPack packing failed")
    validate(greader, gpk, source_manifest)
    raw_gpk = scratch / "zip-edge-cases-raw.gpk"
    require_ok([str(raw_packer), str(root), str(raw_gpk)], "edge-case raw GPack packing failed")
    validate(greader, raw_gpk, source_manifest)
    archives = {}
    for method in ("STORE", "DEFLATE"):
        archive = scratch / f"zip-edge-cases-{method.lower()}.zip"
        require_ok([str(zpack), method, str(root), str(archive)], f"edge-case ZIP {method} packing failed")
        validate(zreader, archive, source_manifest)
        archives[method] = archive
    # Use a two-entry archive so changing the second case variant creates an
    # adjacent duplicate in sorted central-directory order.
    dup_root = scratch / "duplicate-path-source"
    dup_root.mkdir()
    (dup_root / "Case.txt").write_bytes(b"upper")
    (dup_root / "case.txt").write_bytes(b"lower")
    dup_manifest = scratch / "duplicate-path-source.crc.tsv"
    manifest(dup_root, dup_manifest)
    dup_archive = scratch / "duplicate-path-source.zip"
    require_ok([str(zpack), "STORE", str(dup_root), str(dup_archive)], "duplicate fixture packing failed")
    original = dup_archive.read_bytes()
    eocd_at = original.rfind(b"PK\x05\x06")
    at = int.from_bytes(original[eocd_at + 16:eocd_at + 20], "little")
    entries = []
    while at < eocd_at:
        nlen = int.from_bytes(original[at + 28:at + 30], "little")
        elen = int.from_bytes(original[at + 30:at + 32], "little")
        clen = int.from_bytes(original[at + 32:at + 34], "little")
        entries.append((at, original[at + 46:at + 46 + nlen]))
        at += 46 + nlen + elen + clen
    names = [name for _, name in entries]
    first_case = names.index(b"Case.txt")
    second_case = names.index(b"case.txt")
    if first_case + 1 != second_case:
        raise RuntimeError("expected byte-sorted Case.txt/case.txt adjacent in edge archive")
    duplicate = bytearray(original)
    entry_offset, entry_name = entries[second_case]
    duplicate[entry_offset + 46:entry_offset + 46 + len(entry_name)] = b"Case.txt"
    duplicate_path = scratch / "malformed-duplicate-path.zip"
    duplicate_path.write_bytes(duplicate)
    duplicate_rejected = run([str(zreader), str(duplicate_path), str(dup_manifest), "validate"]).returncode != 0
    if not duplicate_rejected:
        raise RuntimeError("ZIP reader accepted duplicate path")
    traversal = bytearray(archives["STORE"].read_bytes())
    eocd_at = traversal.rfind(b"PK\x05\x06")
    at = int.from_bytes(traversal[eocd_at + 16:eocd_at + 20], "little")
    traversal_name, traversal_local = None, None
    while at < eocd_at:
        nlen = int.from_bytes(traversal[at + 28:at + 30], "little")
        elen = int.from_bytes(traversal[at + 30:at + 32], "little")
        clen = int.from_bytes(traversal[at + 32:at + 34], "little")
        current_name = bytes(traversal[at + 46:at + 46 + nlen])
        if current_name == b"a/b":
            traversal_name = at + 46
            traversal_local = int.from_bytes(traversal[at + 42:at + 46], "little") + 30
            break
        at += 46 + nlen + elen + clen
    if traversal_name is None or traversal_local is None:
        raise RuntimeError("could not locate traversal-path fixture entry")
    traversal[traversal_name:traversal_name + 3] = b"../"
    traversal[traversal_local:traversal_local + 3] = b"../"
    traversal_path = scratch / "malformed-traversal-path.zip"
    traversal_path.write_bytes(traversal)
    traversal_rejected = run([str(zreader), str(traversal_path), str(source_manifest), "validate"]).returncode != 0
    if not traversal_rejected:
        raise RuntimeError("ZIP reader accepted traversal path")
    oversized_root = scratch / "oversized-source"
    oversized_root.mkdir()
    (oversized_root / "above-limit.bin").write_bytes(b"\0" * (32 * 1024 * 1024 + 1))
    oversized_manifest = scratch / "oversized-source.crc.tsv"
    manifest(oversized_root, oversized_manifest)
    oversized_archive = scratch / "oversized-source.zip"
    require_ok([str(zpack), "STORE", str(oversized_root), str(oversized_archive)], "oversized fixture packing failed")
    oversized_rejected = run([str(zreader), str(oversized_archive), str(oversized_manifest), "validate"]).returncode != 0
    if not oversized_rejected:
        raise RuntimeError("ZIP reader accepted an asset above the 32 MiB read limit")
    return {"file_count": count, "source_bytes": byte_count, "empty_file": True,
            "utf8_path": True, "case_distinct_paths": True, "nested_path": True,
            "four_reader_concurrency": True, "duplicate_path_rejected": duplicate_rejected,
            "traversal_path_rejected": traversal_rejected, "above_32_mib_asset_rejected": oversized_rejected,
            "gpack_raw_full_read_crc_pass": True, "gpack_full_read_crc_pass": True, "zip_store_full_read_crc_pass": True,
            "zip_deflate_full_read_crc_pass": True}


def parse_metric(proc: subprocess.CompletedProcess[str], label: str, pattern: re.Pattern[str]) -> dict:
    match, rss = pattern.search(proc.stdout), RSS.search(proc.stderr)
    if proc.returncode or not match or not rss:
        raise RuntimeError(f"{label} failed: {proc.stderr[-1200:]} {proc.stdout[-500:]}")
    files, nbytes, parse_ns, lookup_ns, mib_s, p50, p95 = match.groups()
    return {"files": int(files), "bytes": int(nbytes), "parse_ns": int(parse_ns),
            "lookup_ns": int(lookup_ns), "mib_s": float(mib_s), "p50_ms": float(p50),
            "p95_ms": float(p95), "peak_rss_kib": int(rss.group(1))}


def summarize(rows: list[dict], keys: tuple[str, ...]) -> dict:
    return {key: {"median": statistics.median(row[key] for row in rows),
                  "min": min(row[key] for row in rows), "max": max(row[key] for row in rows)} for key in keys}


def main() -> None:
    if len(sys.argv) != 8:
        raise SystemExit("usage: bench.py SMALL_ROOT LARGE_ROOT GPACK_CLI GOOSE_READER ZIP_PACKER ZIP_READER RAW_GPACK_PACKER")
    small, large, gpack, greader, zpack, zreader, raw_packer = map(lambda item: pathlib.Path(item).resolve(), sys.argv[1:])
    for path in (small, large, gpack, greader, zpack, zreader, raw_packer):
        if not path.exists():
            raise SystemExit(f"missing benchmark input: {path}")
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="gpack-zip-comparison-"))
    env = os.environ.copy()
    try:
        generated = h2.create_inputs(scratch / "generated", small)
        workloads = [("godot-real", generated["godot-real"]), ("mixed", generated["mixed"]),
                     ("godot-material-testers", large)]
        prepared = {}
        correctness: dict[str, dict] = {}
        # Complete all source-manifest, archive, read, CRC, and malformed-input gates before timing.
        for name, root in workloads:
            source_manifest = scratch / f"{name}.crc.tsv"
            file_count, byte_count = manifest(root, source_manifest)
            manifest_sha256 = hashlib.sha256(source_manifest.read_bytes()).hexdigest()
            artifacts = {"root": root, "manifest": source_manifest, "manifest_sha256": manifest_sha256,
                         "files": file_count, "source_bytes": byte_count}
            gpk = scratch / f"{name}.gpk"
            require_ok([str(gpack), "pack", str(root), str(gpk)], f"GPack pack failed: {name}")
            validate(greader, gpk, source_manifest)
            artifacts["gpk"] = gpk
            raw_gpk = scratch / f"{name}-raw.gpk"
            require_ok([str(raw_packer), str(root), str(raw_gpk)], f"raw GPack pack failed: {name}")
            validate(greader, raw_gpk, source_manifest)
            artifacts["raw_gpk"] = raw_gpk
            for method in ("STORE", "DEFLATE"):
                zipped = scratch / f"{name}-{method.lower()}.zip"
                require_ok([str(zpack), method, str(root), str(zipped)], f"ZIP {method} pack failed: {name}")
                validate(zreader, zipped, source_manifest)
                artifacts[method] = zipped
            if name == "godot-real":
                artifacts["zip_malformed_rejection"] = zip_malformed_checks(zreader, zpack, artifacts["STORE"], source_manifest, scratch)
            prepared[name] = artifacts
            correctness[name] = {"files": file_count, "source_bytes": byte_count,
                                 "gpack_raw_full_read_crc_pass": True,
                                 "gpack_full_read_crc_pass": True, "zip_store_full_read_crc_pass": True,
                                 "zip_deflate_full_read_crc_pass": True}
        # External interoperability sanity check after the Goose reader gates.
        for name, data in prepared.items():
            for method in ("STORE", "DEFLATE"):
                require_ok(["unzip", "-t", str(data[method])], f"unzip interoperability check failed: {name}/{method}")
        edge_correctness = edge_case_checks(gpack, raw_packer, greader, zpack, zreader, scratch)

        observations, workload_meta, summaries = [], {}, {}
        for name, data in prepared.items():
            cases = [("gpack-raw", raw_packer, data["raw_gpk"], GPK_METRIC),
                     ("gpack-zstd-raw", gpack, data["gpk"], GPK_METRIC),
                     ("zip-store", zpack, data["STORE"], ZIP_METRIC),
                     ("zip-deflate-3", zpack, data["DEFLATE"], ZIP_METRIC)]
            packed_runs = {label: {"seconds": [], "hashes": [], "sizes": [], "rss_kib": []} for label, *_ in cases}
            for pair in range(1, 6):
                pack_order = cases if pair % 2 else list(reversed(cases))
                for label, packer, _source_archive, _ in pack_order:
                    target = scratch / f"{name}-{label}-pack-{pair}.archive"
                    if label == "gpack-zstd-raw":
                        command = [str(packer), "pack", str(data["root"]), str(target)]
                    elif label == "gpack-raw":
                        command = [str(packer), str(data["root"]), str(target)]
                    else:
                        command = [str(packer), "STORE" if label == "zip-store" else "DEFLATE", str(data["root"]), str(target)]
                    start = time.perf_counter()
                    proc = run(["/usr/bin/time", "-f", "GPACK_V1_RSS_KIB=%M", *command])
                    elapsed = time.perf_counter() - start
                    if proc.returncode:
                        raise RuntimeError(f"packing run failed ({name}/{label}): {proc.stderr[-1200:]}")
                    packed_runs[label]["seconds"].append(elapsed)
                    packed_runs[label]["hashes"].append(hashlib.sha256(target.read_bytes()).hexdigest())
                    packed_runs[label]["sizes"].append(target.stat().st_size)
                    rss_match = RSS.search(proc.stderr)
                    if not rss_match:
                        raise RuntimeError("GNU time did not report packer peak RSS")
                    packed_runs[label]["rss_kib"].append(int(rss_match.group(1)))
                    target.unlink()
            archive_meta = {}
            for label, *_ in cases:
                run_data = packed_runs[label]
                if len(set(run_data["hashes"])) != 1 or len(set(run_data["sizes"])) != 1:
                    raise RuntimeError(f"nondeterministic archive output: {name}/{label}")
                archive_meta[label] = {"archive_bytes": run_data["sizes"][0], "archive_sha256": run_data["hashes"][0],
                                       "pack_seconds": {"median": statistics.median(run_data["seconds"]), "runs": run_data["seconds"]},
                                       "pack_peak_rss_kib": {"median": statistics.median(run_data["rss_kib"]), "runs": run_data["rss_kib"]},
                                       "paired_order": [[case[0] for case in (cases if pair % 2 else list(reversed(cases)))] for pair in range(1, 6)]}
            archive_meta["gpack-zstd-raw"]["archive_bytes"] = data["gpk"].stat().st_size
            archive_meta["gpack-zstd-raw"]["archive_sha256"] = hashlib.sha256(data["gpk"].read_bytes()).hexdigest()
            archive_meta["zip-store"]["archive_bytes"] = data["STORE"].stat().st_size
            archive_meta["zip-store"]["archive_sha256"] = hashlib.sha256(data["STORE"].read_bytes()).hexdigest()
            archive_meta["zip-deflate-3"]["archive_bytes"] = data["DEFLATE"].stat().st_size
            archive_meta["zip-deflate-3"]["archive_sha256"] = hashlib.sha256(data["DEFLATE"].read_bytes()).hexdigest()
            workload_meta[name] = {"files": data["files"], "source_bytes": data["source_bytes"],
                                   "source_manifest_sha256": data["manifest_sha256"], "archives": archive_meta}
            for pair in range(1, 6):
                order = cases if pair % 2 else list(reversed(cases))
                for label, _packer, archive, pattern in order:
                    proc = run(["/usr/bin/time", "-f", "GPACK_V1_RSS_KIB=%M", str(greader if label.startswith("gpack-") else zreader), str(archive), str(data["manifest"])])
                    row = parse_metric(proc, label, pattern)
                    if row["files"] != data["files"] or row["bytes"] != data["source_bytes"]:
                        raise RuntimeError(f"source mismatch while reading: {name}/{label}")
                    row.update({"workload": name, "format": label, "paired_run": pair,
                                "execution_order": [case[0] for case in order]})
                    observations.append(row)
            summaries[name] = {label: summarize([row for row in observations if row["workload"] == name and row["format"] == label],
                                                 ("parse_ns", "lookup_ns", "mib_s", "p50_ms", "p95_ms", "peak_rss_kib"))
                               for label, *_ in cases}
        cpu = next((line.split(":", 1)[1].strip() for line in pathlib.Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), platform.processor())
        output = {"experiment": "Restricted Goose ZIP vs GPack v1", "date": datetime.now(ZoneInfo("Asia/Kolkata")).date().isoformat(),
                  "paired_runs": 5, "reader_threads": 4, "reader_limit_bytes": 32 * 1024 * 1024,
                  "build_mode": os.environ.get("GPACK_BUILD_DESCRIPTION", "unspecified"),
                  "machine": {"os": platform.platform(), "cpu": cpu, "ram_bytes": os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES"),
                              "goose": run(["./goose-bin/goose", "--version"]).stdout.strip(),
                              "cc": run(["gcc", "--version"]).stdout.splitlines()[0],
                              "zstd": run(["pkg-config", "--modversion", "libzstd"]).stdout.strip(),
                              "zlib": run(["pkg-config", "--modversion", "zlib"]).stdout.strip()},
                  "correctness": correctness, "edge_case_correctness": edge_correctness,
                  "malformed_rejection": prepared["godot-real"]["zip_malformed_rejection"],
                  "unzip_interoperability_pass": True,
                  "workload_metadata": workload_meta, "summaries": summaries,
                  "observations": observations}
        destination = HERE / "results.json"
        destination.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"results": str(destination), "correctness": correctness, "summaries": summaries}, indent=2))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()
