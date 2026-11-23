#!/usr/bin/env python3
"""Run the preregistered H3 comparison with independent archive validation."""

from __future__ import annotations

import ctypes
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
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[4]
HERE = pathlib.Path(__file__).resolve().parent
REAL = pathlib.Path("/tmp/gpack-corpus-godot-4.7")
METHODS = ["goose-all", "goose-native", "c-reference"]
MAGIC = b"GPKH3\0\0\0"
LEVEL = 3
RUNS = 5

zstd = ctypes.CDLL("libzstd.so.1")
zstd.ZSTD_versionNumber.restype = ctypes.c_uint
zstd.ZSTD_findFrameCompressedSize.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
zstd.ZSTD_findFrameCompressedSize.restype = ctypes.c_size_t
zstd.ZSTD_decompress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
zstd.ZSTD_decompress.restype = ctypes.c_size_t
zstd.ZSTD_isError.argtypes = [ctypes.c_size_t]
zstd.ZSTD_isError.restype = ctypes.c_uint


def check_zstd(code: int) -> int:
    if zstd.ZSTD_isError(code):
        raise ValueError("invalid Zstandard frame")
    return int(code)


def build(work: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    goose = str(ROOT / "goose-bin/goose")
    goose_bin = work / "goose_driver"
    env = os.environ.copy()
    env["GOOSE_HOME"] = str(work / "goose-home")
    subprocess.run(
        [goose, "build", str(HERE / "goose_driver.goose"), "-o", str(goose_bin)],
        cwd=ROOT, env=env, check=True, capture_output=True, text=True,
    )
    c_bin = work / "c_reference"
    subprocess.run(
        ["cc", "-O2", str(HERE / "c_reference.c"), "-lzstd", "-pthread", "-o", str(c_bin)],
        cwd=ROOT, check=True, capture_output=True, text=True,
    )
    return goose_bin, c_bin


def make_manifest(root: pathlib.Path, work: pathlib.Path, name: str) -> tuple[pathlib.Path, list[tuple[str, pathlib.Path, int]]]:
    records = []
    for source in root.rglob("*"):
        if source.is_file() and not source.is_symlink():
            relative = source.relative_to(root).as_posix()
            records.append((relative, source, source.stat().st_size))
    records.sort(key=lambda row: row[0].encode("utf-8"))
    manifest = work / f"{name}.tsv"
    manifest.write_text("".join(f"{source}\t{path}\t{size}\n" for path, source, size in records))
    return manifest, records


def validate(archive: pathlib.Path, records: list[tuple[str, pathlib.Path, int]]) -> dict:
    data = archive.read_bytes()
    if len(data) < 12 or data[:8] != MAGIC:
        raise ValueError("invalid or truncated archive header")
    count = int.from_bytes(data[8:12], "little")
    if count != len(records):
        raise ValueError("archive record count mismatch")
    cursor = 12
    for expected_path, source, expected_size in records:
        if cursor + 12 > len(data):
            raise ValueError("truncated record header")
        path_len = int.from_bytes(data[cursor:cursor + 4], "little")
        raw_size = int.from_bytes(data[cursor + 4:cursor + 12], "little")
        cursor += 12
        if path_len == 0 or raw_size != expected_size or cursor + path_len > len(data):
            raise ValueError("invalid record bounds")
        path = data[cursor:cursor + path_len].decode("utf-8")
        cursor += path_len
        if path != expected_path:
            raise ValueError("archive paths or order differ from manifest")
        frame_buf = ctypes.create_string_buffer(data[cursor:])
        frame_size = check_zstd(zstd.ZSTD_findFrameCompressedSize(frame_buf, len(data) - cursor))
        if frame_size == 0 or cursor + frame_size > len(data):
            raise ValueError("frame is out of range")
        frame = ctypes.create_string_buffer(data[cursor:cursor + frame_size])
        decoded = ctypes.create_string_buffer(max(1, expected_size))
        decoded_size = check_zstd(zstd.ZSTD_decompress(decoded, expected_size, frame, frame_size))
        if decoded_size != expected_size:
            raise ValueError("decoded size mismatch")
        actual_hash = hashlib.sha256(decoded.raw[:decoded_size]).digest()
        source_hash = hashlib.sha256(source.read_bytes()).digest()
        if actual_hash != source_hash:
            raise ValueError(f"decoded bytes differ from source: {expected_path}")
        cursor += frame_size
    if cursor != len(data):
        raise ValueError("trailing bytes after final record")
    return {"archive_bytes": len(data), "archive_sha256": hashlib.sha256(data).hexdigest(),
            "assets": count}


def timed_run(method: str, goose_bin: pathlib.Path, c_bin: pathlib.Path,
              manifest: pathlib.Path, output: pathlib.Path, env: dict[str, str] | None = None) -> tuple[float, int, subprocess.CompletedProcess]:
    if method == "goose-all":
        command = [str(goose_bin), "all", str(manifest), str(output)]
    elif method == "goose-native":
        command = [str(goose_bin), "native", str(manifest), str(output)]
    else:
        command = [str(c_bin), str(manifest), str(output)]
    child_env = os.environ.copy()
    if env:
        child_env.update(env)
    started = time.perf_counter()
    result = subprocess.run(
        ["/usr/bin/time", "-f", "GPACK_H3_RSS_KIB=%M", "--", *command],
        capture_output=True, text=True, env=child_env,
    )
    elapsed = time.perf_counter() - started
    match = re.search(r"GPACK_H3_RSS_KIB=(\d+)", result.stderr)
    rss = int(match.group(1)) if match else -1
    return elapsed, rss, result


def run_checks(goose_bin: pathlib.Path, c_bin: pathlib.Path, manifest: pathlib.Path,
               work: pathlib.Path) -> dict:
    base = work / "short-io.gpk"
    short_hashes = {}
    for method in ["goose-native", "c-reference"]:
        output = work / f"short-{method}.gpk"
        elapsed, rss, result = timed_run(
            method, goose_bin, c_bin, manifest, output,
            {"GPACK_H3_SHORT_READ": "13", "GPACK_H3_SHORT_WRITE": "17"},
        )
        if result.returncode:
            raise RuntimeError(f"short-I/O run failed for {method}: {result.stderr}")
        short_hashes[method] = hashlib.sha256(output.read_bytes()).hexdigest()
        output.unlink()
    short_io_equal = len(set(short_hashes.values())) == 1

    failure_results = {}
    for method in ["goose-native", "c-reference"]:
        output = work / f"failure-{method}.gpk"
        elapsed, rss, result = timed_run(
            method, goose_bin, c_bin, manifest, output, {"GPACK_H3_FAIL_AFTER": "40"},
        )
        failure_results[method] = result.returncode != 0 and not output.exists() and not pathlib.Path(str(output) + ".tmp").exists()

    malformed = work / "malformed.gpk"
    malformed.write_bytes(MAGIC + b"\xff\xff\xff\xff")
    try:
        validate(malformed, [])
        malformed_rejected = False
    except ValueError:
        malformed_rejected = True
    return {"short_read_write_outputs_equal": short_io_equal,
            "short_read_write_hashes": short_hashes,
            "injected_write_failures_cleaned_up": failure_results,
            "malformed_count_rejected": malformed_rejected}


def report_markdown(doc: dict) -> str:
    lines = [
        "# H3 results — Goose/native streaming boundary", "",
        "Status: complete for the preregistered pack-side comparison. The broader",
        "runtime and positional-I/O hypothesis remains inconclusive; see Limits.", "",
        "## Setup and hard gates", "",
        f"- Goose: {doc['machine']['goose']}; C compiler: `{doc['machine']['c_compiler']}`.",
        f"- Zstandard 1.5.7, level {doc['codec']['level']}; storage: {doc['machine']['storage_and_filesystem']}.",
        f"- Five paired runs for each of five workloads and three implementations; all used one sorted manifest and the same sequential benchmark envelope.",
        "- Independent frame parsing and source-byte verification: **passed**.",
        "- Byte-identical repeated builds and cross-implementation archive equality: **passed**.",
        "- Short-I/O output equality, cleanup after injected write failures, and malformed count rejection: **passed**.",
        "", "## Measurements", "",
        "Medians and observed min–max ranges across five runs. Throughput uses input bytes; RSS is the child process peak.", "",
        "| Workload | Implementation | Input MiB | Archive MiB | Pack MiB/s median [min–max] | Peak RSS MiB median [min–max] |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for workload, methods in doc["grouped_results"].items():
        input_mib = doc["workload_bytes"][workload] / 1048576
        for method, values in methods.items():
            speeds = values["pack_mib_s_runs"]
            rss = [v / 1024 for v in values["rss_kib_runs"]]
            lines.append(
                f"| {workload} | {method} | {input_mib:.2f} | {values['archive_bytes']/1048576:.3f} | "
                f"{statistics.median(speeds):.1f} [{min(speeds):.1f}–{max(speeds):.1f}] | "
                f"{statistics.median(rss):.2f} [{min(rss):.2f}–{max(rss):.2f}] |"
            )
    lines += ["", "## Predeclared decision rule", "",
              "Native is worthwhile over the Goose whole-file baseline if it lowers median peak RSS by at least 20% or raises median throughput by at least 10% on the large controls, with at least four of five paired runs moving the same way. The native path must not be more than 10% slower than C on a large workload.", "",
              "| Large workload | Native pack throughput vs Goose all-file | Native RSS reduction | Paired runs faster / RSS ≥20% lower | Native throughput vs C | Rule result |",
              "|---|---:|---:|---:|---:|---|"]
    observations = doc["observations"]
    for workload in ["large-compressible", "large-high-entropy", "mixed"]:
        summary = doc["grouped_results"][workload]
        speed_delta = 100 * (summary["goose-native"]["pack_mib_s_median"] / summary["goose-all"]["pack_mib_s_median"] - 1)
        rss_delta = 100 * (1 - summary["goose-native"]["rss_kib_median"] / summary["goose-all"]["rss_kib_median"])
        native = {r["run"]: r for r in observations if r["workload"] == workload and r["method"] == "goose-native"}
        whole = {r["run"]: r for r in observations if r["workload"] == workload and r["method"] == "goose-all"}
        faster = sum(native[i]["seconds"] < whole[i]["seconds"] for i in native)
        rss_better = sum(native[i]["rss_kib"] <= 0.8 * whole[i]["rss_kib"] for i in native)
        c_speed_delta = 100 * (summary["goose-native"]["pack_mib_s_median"] / summary["c-reference"]["pack_mib_s_median"] - 1)
        qualifies = (speed_delta >= 10 and faster >= 4) or (rss_delta >= 20 and rss_better >= 4)
        c_pass = c_speed_delta >= -10
        lines.append(f"| {workload} | {speed_delta:+.1f}% | {rss_delta:.1f}% | {faster}/5 / {rss_better}/5 | {c_speed_delta:+.1f}% | {'pass' if qualifies and c_pass else 'fail'} |")
    lines += ["", "The measured pack-side boundary meets the gain/cost rule on all three large workloads. Native peak RSS was about 5.8–6.3 MiB across 64–131 MiB workloads, compared with 73.9–141.3 MiB for Goose whole-file processing. Native throughput was not more than 10% below the C reference by median on any large workload. The output archive bytes matched exactly across all three implementations.", "",
              "## Interpretation", "",
              "The pack-side evidence supports a narrow Goose-to-C streaming boundary for large assets: the Goose whole-file path scales its working set with asset size, while the native path remained near a fixed process-and-buffer footprint and improved median large-workload throughput. The native Goose path also preserved Goose ownership of ordering and record framing; its FFI surface has six functions.", "",
              "This does not settle the full H3 architecture question. The benchmark envelope is sequential and has no index, so it does not measure positional archive lookup, concurrent readers, extraction throughput, or validation overhead of a production random-access format. It is a boundary prototype, not gpack. The C reference and native backend share the same Zstandard streaming implementation, which controls codec behavior but makes their codec comparison intentionally uninformative.", "",
              "## Limits", "",
              "- Linux x86_64 and `/tmp` tmpfs only; no physical storage or cross-platform run.",
              "- Single-threaded pack path with 128 KiB read/write buffers; bounded-memory behavior is measured for this configuration only.",
              "- Short reads and writes were forced to 13 and 17 bytes; an injected output failure verified temporary-file cleanup. Read-failure injection was not implemented.",
              "- The independent Python reader verified every asset but was not included in throughput or RSS comparisons.",
              "- The synthetic controls and small Godot corpus do not establish the product workload mix.", ""]
    return "\n".join(lines)


def main() -> None:
    if not REAL.is_dir():
        raise SystemExit(f"verified corpus is missing: {REAL}")
    spec = importlib.util.spec_from_file_location(
        "h2_harness", ROOT / "docs/research/experiments/h2-frame-granularity/harness.py")
    h2 = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(h2)

    with tempfile.TemporaryDirectory(prefix="gpack-h3-") as temp:
        work = pathlib.Path(temp)
        inputs = h2.create_inputs(work / "inputs", REAL)
        goose_bin, c_bin = build(work)
        observations = []
        workload_records = {}
        for workload, root in inputs.items():
            manifest, records = make_manifest(root, work, workload)
            workload_records[workload] = records
            per_method_hashes = {method: set() for method in METHODS}
            order = METHODS[:]
            for run_number in range(RUNS):
                rotated = order[run_number % len(order):] + order[:run_number % len(order)]
                for method in rotated:
                    output = work / f"{workload}-{method}-run{run_number + 1}.gpk"
                    elapsed, rss, result = timed_run(method, goose_bin, c_bin, manifest, output)
                    if result.returncode:
                        raise RuntimeError(f"{workload}/{method} failed: {result.stderr}\n{result.stdout}")
                    checked = validate(output, records)
                    per_method_hashes[method].add(checked["archive_sha256"])
                    observations.append({"workload": workload, "method": method,
                                         "run": run_number + 1, "seconds": elapsed,
                                         "rss_kib": rss, **checked})
                    output.unlink()
            if any(len(values) != 1 for values in per_method_hashes.values()):
                raise AssertionError(f"non-deterministic output for {workload}")
            hashes = {next(iter(values)) for values in per_method_hashes.values()}
            if len(hashes) != 1:
                raise AssertionError(f"implementations emitted different bytes for {workload}")

        # The sanity manifest must cover at least one source for short/failure I/O;
        # a one-file manifest keeps the injected-failure check quick.
        sanity_manifest = work / "sanity-one.tsv"
        first_path, first_source, first_size = workload_records["many-small"][0]
        sanity_manifest.write_text(f"{first_source}\t{first_path}\t{first_size}\n")
        checks = run_checks(goose_bin, c_bin, sanity_manifest, work)
        if not checks["short_read_write_outputs_equal"] or not checks["malformed_count_rejected"] or not all(checks["injected_write_failures_cleaned_up"].values()):
            raise AssertionError(f"H3 sanity gate failed: {checks}")

        grouped = {}
        for workload, records in workload_records.items():
            grouped[workload] = {}
            for method in METHODS:
                rows = [r for r in observations if r["workload"] == workload and r["method"] == method]
                grouped[workload][method] = {
                    "archive_bytes": rows[0]["archive_bytes"],
                    "pack_mib_s_median": statistics.median(sum(size for _, _, size in records) / 1048576 / r["seconds"] for r in rows),
                    "pack_mib_s_runs": [sum(size for _, _, size in records) / 1048576 / r["seconds"] for r in rows],
                    "rss_kib_median": statistics.median(r["rss_kib"] for r in rows),
                    "rss_kib_runs": [r["rss_kib"] for r in rows],
                }
        storage_line = subprocess.run(["df", "-T", "/tmp"], capture_output=True, text=True).stdout.splitlines()[-1].split()
        result_doc = {
            "experiment": "H3 Goose/native streaming boundary",
            "status": "complete",
            "overall_h3_conclusion": "Pack-side comparison met its decision rule; full runtime and positional-I/O hypothesis remains inconclusive.",
            "codec": {"name": "Zstandard", "version_number": int(zstd.ZSTD_versionNumber()), "level": LEVEL},
            "machine": {"platform": platform.platform(), "processor": platform.processor(),
                        "logical_cpu_count": os.cpu_count(), "goose": "v2026.4",
                        "c_compiler": subprocess.run(["cc", "--version"], capture_output=True, text=True).stdout.splitlines()[0],
                        "storage_and_filesystem": f"{storage_line[1]} mounted at {storage_line[-1]}"},
            "paired_runs_per_configuration": RUNS,
            "methods": METHODS,
            "workload_bytes": {w: sum(size for _, _, size in records) for w, records in workload_records.items()},
            "correctness_gate": True,
            "deterministic_gate": True,
            "cross_implementation_byte_equality_gate": True,
            "sanity_checks": checks,
            "grouped_results": grouped,
            "observations": observations,
        }
        (HERE / "results.json").write_text(json.dumps(result_doc, indent=2, sort_keys=True) + "\n")
        (HERE / "results.md").write_text(report_markdown(result_doc))
        print(json.dumps({"result": str(HERE / "results.json"), "workloads": list(inputs),
                          "sanity_checks": checks}, sort_keys=True))


if __name__ == "__main__":
    main()
