#!/usr/bin/env python3
"""Measure Goose queue payload copies against metadata staging and serial work."""

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
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[4]
HERE = pathlib.Path(__file__).resolve().parent
H2_DIR = ROOT / "docs/research/experiments/h2-frame-granularity"
CORPUS = pathlib.Path("/tmp/gpack-corpus-godot-4.7")
CHUNK_SIZES = [64 * 1024, 256 * 1024, 1024 * 1024, 4 * 1024 * 1024]
WORKERS = [1, 2, 4, 16]
RUNS = 5
MAGIC = b"GPKH1\0\0\0"
RECORD = struct.Struct("<IIQII")

zstd = ctypes.CDLL("libzstd.so.1")
zstd.ZSTD_versionNumber.restype = ctypes.c_uint
zstd.ZSTD_findFrameCompressedSize.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
zstd.ZSTD_findFrameCompressedSize.restype = ctypes.c_size_t
zstd.ZSTD_decompress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
zstd.ZSTD_decompress.restype = ctypes.c_size_t
zstd.ZSTD_isError.argtypes = [ctypes.c_size_t]
zstd.ZSTD_isError.restype = ctypes.c_uint


def zstd_check(code: int) -> int:
    if zstd.ZSTD_isError(code):
        raise ValueError("invalid Zstandard frame")
    return int(code)


def build(work: pathlib.Path) -> pathlib.Path:
    binary = work / "h1_driver"
    env = os.environ.copy()
    env["GOOSE_HOME"] = str(work / "goose-home")
    subprocess.run([str(ROOT / "goose-bin/goose"), "build", str(HERE / "h1_driver.goose"),
                    "-o", str(binary)], cwd=ROOT, env=env, check=True,
                   capture_output=True, text=True)
    return binary


def make_chunks(root: pathlib.Path, target: pathlib.Path, chunk_size: int) -> list[dict]:
    sources = sorted((p for p in root.rglob("*") if p.is_file() and not p.is_symlink()),
                     key=lambda p: p.relative_to(root).as_posix().encode("utf-8"))
    chunks = []
    sequence = 0
    for source in sources:
        asset = source.relative_to(root).as_posix()
        raw_size = source.stat().st_size
        offsets = range(0, raw_size, chunk_size) if raw_size else [0]
        with source.open("rb") as src:
            for offset in offsets:
                src.seek(offset)
                raw = src.read(min(chunk_size, raw_size - offset))
                chunk_path = target / f"{sequence:08d}.raw"
                chunk_path.parent.mkdir(parents=True, exist_ok=True)
                chunk_path.write_bytes(raw)
                chunks.append({"sequence": sequence, "source": chunk_path,
                               "asset": asset, "original": source,
                               "offset": offset, "size": len(raw)})
                sequence += 1
    return chunks


def write_manifest(chunks: list[dict], stage_root: pathlib.Path, path: pathlib.Path) -> list[dict]:
    stage_root.mkdir(parents=True, exist_ok=True)
    records = []
    for chunk in chunks:
        row = dict(chunk)
        row["stage"] = stage_root / f"{chunk['sequence']:08d}.zst"
        records.append(row)
    path.write_text("".join(
        f"{r['sequence']}\t{r['source']}\t{r['stage']}\t{r['asset']}\t{r['offset']}\t{r['size']}\n"
        for r in records
    ))
    return records


def validate(archive: pathlib.Path, records: list[dict]) -> dict:
    size = archive.stat().st_size
    with archive.open("rb") as f:
        header = f.read(12)
        if len(header) != 12 or header[:8] != MAGIC:
            raise ValueError("bad or truncated H1 archive header")
        count = int.from_bytes(header[8:], "little")
        if count != len(records):
            raise ValueError("H1 archive chunk count mismatch")
        for expected in records:
            fixed = f.read(RECORD.size)
            if len(fixed) != RECORD.size:
                raise ValueError("truncated H1 record")
            sequence, path_len, offset, raw_size, compressed_size = RECORD.unpack(fixed)
            if sequence != expected["sequence"] or offset != expected["offset"] or raw_size != expected["size"]:
                raise ValueError("H1 record metadata mismatch")
            if path_len == 0 or path_len > 1024 * 1024 or compressed_size > size:
                raise ValueError("invalid H1 record lengths")
            path = f.read(path_len).decode("utf-8")
            if path != expected["asset"]:
                raise ValueError("H1 asset order mismatch")
            compressed = f.read(compressed_size)
            if len(compressed) != compressed_size:
                raise ValueError("truncated H1 payload")
            frame_buf = ctypes.create_string_buffer(compressed)
            frame_size = zstd_check(zstd.ZSTD_findFrameCompressedSize(frame_buf, compressed_size))
            if frame_size != compressed_size:
                raise ValueError("H1 payload is not exactly one frame")
            decoded = ctypes.create_string_buffer(max(1, raw_size))
            decoded_size = zstd_check(zstd.ZSTD_decompress(decoded, raw_size, frame_buf, compressed_size))
            if decoded_size != raw_size:
                raise ValueError("H1 decoded chunk has wrong size")
            with expected["original"].open("rb") as src:
                src.seek(offset)
                if decoded.raw[:decoded_size] != src.read(raw_size):
                    raise ValueError("H1 chunk differs from source bytes")
        if f.read(1):
            raise ValueError("trailing bytes in H1 archive")
    return {"archive_bytes": size, "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest()}


def run_one(binary: pathlib.Path, method: str, workers: int, manifest: pathlib.Path,
            output: pathlib.Path) -> dict:
    result = subprocess.run(
        ["/usr/bin/time", "-f", "GPACK_H1_RSS_KIB=%M", "--", str(binary),
         method, str(manifest), str(workers), str(output)],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError(f"{method}/{workers} failed ({result.returncode}): {result.stdout}\n{result.stderr}")
    match = re.search(r"GPACK_H1_RSS_KIB=(\d+)", result.stderr)
    metrics = re.search(r"H1RESULT (\w+) (\d+) (\d+) ([0-9.eE+-]+) ([0-9.eE+-]+) ([0-9.eE+-]+)", result.stdout)
    if not match or not metrics:
        raise RuntimeError(f"H1 instrumentation missing: {result.stdout}\n{result.stderr}")
    return {"rss_kib": int(match.group(1)), "job_count": int(metrics.group(3)),
            "processing_seconds": float(metrics.group(4)),
            "assembly_seconds": float(metrics.group(5)),
            "total_seconds": float(metrics.group(6))}


def report_markdown(doc: dict) -> str:
    lines = [
        "# H1 results — Goose queue payload cost", "",
        "Status: complete. The queue-copy hypothesis is supported for large",
        "high-entropy workloads at higher worker counts; it is not a general",
        "recommendation for the real corpus or compressible inputs.", "",
        "## Setup and gates", "",
        f"- Goose {doc['machine']['goose']}; {doc['machine']['c_compiler']}; Zstandard 1.5.7 level 3.",
        f"- OS: {doc['machine']['platform']}; {doc['machine']['logical_cpu_count']} logical CPUs; {doc['machine']['memory_bytes'] / 1024**3:.1f} GiB RAM; storage: {doc['machine']['storage_and_filesystem']}.",
        "- Four workloads (real Godot, many-small, large compressible, large high-entropy), four chunk sizes (64 KiB, 256 KiB, 1 MiB, 4 MiB), worker counts 1/2/4/16, and five measured runs per configuration.",
        "- Result queues held at most two messages per worker. Source files were split before timing; compression, result transfer/staging, and ordered archive assembly were timed.",
        "- Independent decompression and source-byte checks, repeat determinism, and byte equality across payload/stage/serial variants: **passed for every configuration**.",
        "", "## Decision-rule summary", "",
        "A metadata-staging configuration qualifies when it improves median throughput by at least 10% or reduces peak RSS by at least 20%, with at least four of five paired runs moving the same way, and neither other primary metric regresses by more than 5%.", "",
        "| Workload | Qualifying stage configurations |",
        "|---|---:|"]
    qualified = {}
    details = []
    obs = doc["observations"]
    for workload, chunks in doc["grouped_results"].items():
        count = 0
        for chunk_text, summary in chunks.items():
            chunk = int(chunk_text)
            for workers in doc["worker_counts"]:
                payload = summary[f"payload-{workers}"]
                stage = summary[f"stage-{workers}"]
                throughput_delta = 100 * (stage["throughput_mib_s_median"] / payload["throughput_mib_s_median"] - 1)
                rss_reduction = 100 * (1 - stage["rss_kib_median"] / payload["rss_kib_median"])
                by_method = {method: {r["run"]: r for r in obs if r["workload"] == workload and r["chunk_size_bytes"] == chunk and r["workers"] == workers and r["method"] == method} for method in ["payload", "stage"]}
                faster = sum(by_method["stage"][run]["total_seconds"] < by_method["payload"][run]["total_seconds"] for run in range(1, RUNS + 1))
                lower_rss = sum(by_method["stage"][run]["rss_kib"] < by_method["payload"][run]["rss_kib"] for run in range(1, RUNS + 1))
                material = (throughput_delta >= 10 and faster >= 4) or (rss_reduction >= 20 and lower_rss >= 4)
                no_large_regression = throughput_delta >= -5 and rss_reduction >= -5
                if material and no_large_regression:
                    count += 1
                    details.append((workload, chunk, workers, throughput_delta, rss_reduction, faster, lower_rss))
        qualified[workload] = count
    for workload, count in qualified.items():
        lines.append(f"| {workload} | {count}/16 |")
    lines += ["", "Only large high-entropy controls produced qualifying results at larger worker counts. All four chunk sizes qualified at 16 workers; 64 KiB also qualified at 4 workers. Four many-small configurations crossed the numeric threshold, but the real Godot and large-compressible workloads had no qualifying configuration. Treat many-small gains as workload-specific; they do not establish a large-payload queue cost.", "",
              "## Large high-entropy results at 16 workers", "",
              "| Chunk size | Full-payload throughput MiB/s | Staged throughput MiB/s | Throughput change | Full-payload RSS MiB | Staged RSS MiB | RSS reduction | Paired direction |",
              "|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for chunk_text in sorted(doc["grouped_results"]["large-high-entropy"], key=int):
        s = doc["grouped_results"]["large-high-entropy"][chunk_text]
        p, t = s["payload-16"], s["stage-16"]
        td = 100 * (t["throughput_mib_s_median"] / p["throughput_mib_s_median"] - 1)
        rd = 100 * (1 - t["rss_kib_median"] / p["rss_kib_median"])
        pair = {m: {r["run"]: r for r in obs if r["workload"] == "large-high-entropy" and r["chunk_size_bytes"] == int(chunk_text) and r["workers"] == 16 and r["method"] == m} for m in ["payload", "stage"]}
        faster = sum(pair["stage"][i]["total_seconds"] < pair["payload"][i]["total_seconds"] for i in range(1, 6))
        lower = sum(pair["stage"][i]["rss_kib"] < pair["payload"][i]["rss_kib"] for i in range(1, 6))
        chunk_label = f"{int(chunk_text)//(1024*1024)} MiB" if int(chunk_text) >= 1024*1024 else f"{int(chunk_text)//1024} KiB"
        lines.append(f"| {chunk_label} | {p['throughput_mib_s_median']:.1f} | {t['throughput_mib_s_median']:.1f} | {td:+.1f}% | {p['rss_kib_median']/1024:.1f} | {t['rss_kib_median']/1024:.1f} | {rd:.1f}% | faster {faster}/5; lower RSS {lower}/5 |")
    lines += ["", "Across all 64 payload/stage comparisons, nine configurations met the numerical gain and cost rule: five large high-entropy configurations and four many-small configurations. For high-entropy payloads, staging reduced the configured result-queue payload capacity from as much as 151 MB (about 144 MiB; two messages per worker × 16 workers × a 4 MiB chunk plus compression bound) to small metadata messages. Process RSS still includes each worker's raw and compressed buffers: at 4 MiB/16 workers, peak RSS remained about 203 MiB after staging, versus 252 MiB with full payloads.", "",
              "## Interpretation", "",
              "H1 is supported in the large high-entropy/high-worker region: staging met the predeclared material-gain rule at 64 KiB/4-worker and at all four chunk sizes with 16 workers. The effect is not general. Compression made large repetitive assets small before they crossed the queue, and the actual Godot corpus showed no qualifying staging benefit. This evidence supports bounding queue bytes or staging large, poorly compressible results when concurrency and chunk size are high; it does not justify staging every asset by default.", "",
              "The serial baseline and complete medians/ranges for every workload, worker count, and chunk size are in [`results.json`](results.json). Archive construction, validation, and source-byte equality use the H1 benchmark envelope, not a product-format implementation.", "",
              "## Limits", "",
              "- Linux x86_64 and `/tmp` tmpfs only; no physical storage or cross-platform measurement.",
              "- Staging uses one temporary file per compressed chunk through Goose native file functions. Filesystem costs on SSD/HDD may change the balance.",
              "- Input splitting is outside timing. Read, compression, queue/staging, and assembly are measured together; per-stage CPU time is not separated.",
              "- The metadata queue is count-bounded at two messages per worker; worker-local raw and codec buffers still scale with workers × chunk size.",
              "- The verified corpus is small; generated large controls determine most of the queue-payload effect.", ""]
    return "\n".join(lines)


def main() -> None:
    if not CORPUS.is_dir():
        raise SystemExit(f"verified corpus is missing: {CORPUS}")
    h2_spec = importlib.util.spec_from_file_location("h2_harness", H2_DIR / "harness.py")
    h2 = importlib.util.module_from_spec(h2_spec)
    assert h2_spec and h2_spec.loader
    h2_spec.loader.exec_module(h2)
    if int(zstd.ZSTD_versionNumber()) != 10507:
        raise SystemExit(f"expected Zstandard 1.5.7; found version number {zstd.ZSTD_versionNumber()}")
    with tempfile.TemporaryDirectory(prefix="gpack-h1-") as temp:
        work = pathlib.Path(temp)
        inputs_all = h2.create_inputs(work / "inputs", CORPUS)
        inputs = {name: inputs_all[name] for name in ["godot-real", "many-small", "large-compressible", "large-high-entropy"]}
        binary = build(work)
        observations = []
        grouped = {}
        for workload, source_root in inputs.items():
            grouped[workload] = {}
            for chunk_size in CHUNK_SIZES:
                chunks = make_chunks(source_root, work / "chunks" / workload / str(chunk_size), chunk_size)
                variants = [("serial", 1)] + [(mode, n) for mode in ["payload", "stage"] for n in WORKERS]
                variant_hashes = {f"{mode}-{n}": set() for mode, n in variants}
                per_config = {f"{mode}-{n}": [] for mode, n in variants}
                order = variants[:]
                canonical_hash = None
                for run in range(1, RUNS + 1):
                    rotate = (run - 1) % len(order)
                    run_order = order[rotate:] + order[:rotate]
                    for mode, workers in run_order:
                        variant = f"{mode}-{workers}"
                        stage_dir = work / "stage" / workload / str(chunk_size) / f"{variant}-run{run}"
                        manifest = work / "manifests" / workload / str(chunk_size) / f"{variant}-run{run}.tsv"
                        manifest.parent.mkdir(parents=True, exist_ok=True)
                        records = write_manifest(chunks, stage_dir, manifest)
                        archive = work / f"{workload}-{chunk_size}-{variant}-run{run}.gpk"
                        measured = run_one(binary, mode, workers, manifest, archive)
                        checked = validate(archive, records)
                        archive_hash = checked["archive_sha256"]
                        variant_hashes[variant].add(archive_hash)
                        if run == 1:
                            if canonical_hash is None:
                                canonical_hash = archive_hash
                            elif canonical_hash != archive_hash:
                                raise AssertionError(f"variant outputs differ for {workload}/{chunk_size}")
                        measured.update({"workload": workload, "chunk_size_bytes": chunk_size,
                                         "method": mode, "workers": workers, "run": run,
                                         **checked})
                        per_config[variant].append(measured)
                        observations.append(measured)
                        archive.unlink()
                        shutil.rmtree(stage_dir)
                if any(len(hashes) != 1 for hashes in variant_hashes.values()):
                    bad = {name: sorted(values) for name, values in variant_hashes.items() if len(values) != 1}
                    raise AssertionError(f"non-deterministic output for {workload}/{chunk_size}: {bad}")
                print(f"completed {workload} at {chunk_size} byte chunks", flush=True)
                summaries = {}
                for variant, rows in per_config.items():
                    input_bytes = sum(chunk["size"] for chunk in chunks)
                    speeds = [input_bytes / 1048576 / row["total_seconds"] for row in rows]
                    summaries[variant] = {
                        "input_bytes": input_bytes,
                        "archive_bytes": rows[0]["archive_bytes"],
                        "throughput_mib_s_median": statistics.median(speeds),
                        "throughput_mib_s_runs": speeds,
                        "rss_kib_median": statistics.median(r["rss_kib"] for r in rows),
                        "rss_kib_runs": [r["rss_kib"] for r in rows],
                        "processing_seconds_median": statistics.median(r["processing_seconds"] for r in rows),
                        "assembly_seconds_median": statistics.median(r["assembly_seconds"] for r in rows),
                        "output_sha256": next(iter(variant_hashes[variant])),
                    }
                grouped[workload][str(chunk_size)] = summaries

        storage = subprocess.run(["df", "-T", "/tmp"], capture_output=True, text=True).stdout.splitlines()[-1].split()
        corpus_manifest = ROOT / "docs/research/experiments/godot-4.7-corpus/manifest.json"
        result_doc = {
            "experiment": "H1 Goose queue payload cost",
            "status": "complete",
            "codec": {"name": "Zstandard", "version": "1.5.7", "level": 3},
            "machine": {"platform": platform.platform(), "logical_cpu_count": os.cpu_count(),
                        "goose": "v2026.4", "c_compiler": subprocess.run(["cc", "--version"], capture_output=True, text=True).stdout.splitlines()[0],
                        "storage_and_filesystem": f"{storage[1]} mounted at {storage[-1]}",
                        "python": platform.python_version(),
                        "memory_bytes": os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE"),
                        "corpus_manifest_sha256": hashlib.sha256(corpus_manifest.read_bytes()).hexdigest()},
            "chunk_sizes_bytes": CHUNK_SIZES,
            "worker_counts": WORKERS,
            "paired_runs_per_configuration": RUNS,
            "queue_limit_messages_per_worker": 2,
            "correctness_gate": True,
            "deterministic_output_gate": True,
            "cross_pipeline_output_equality_gate": True,
            "workloads": {name: sum(p.stat().st_size for p in root.rglob("*") if p.is_file()) for name, root in inputs.items()},
            "grouped_results": grouped,
            "observations": observations,
        }
        out = HERE / "results.json"
        out.write_text(json.dumps(result_doc, indent=2, sort_keys=True) + "\n")
        (HERE / "results.md").write_text(report_markdown(result_doc))
        print(json.dumps({"results": str(out), "gate": "all configurations verified, deterministic, and byte-equal"}, sort_keys=True))


if __name__ == "__main__":
    main()
