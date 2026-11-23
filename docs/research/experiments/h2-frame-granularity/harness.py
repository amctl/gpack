#!/usr/bin/env python3
"""Small deterministic archive prototype for H2 framing measurements."""

from __future__ import annotations

import concurrent.futures
import ctypes
import hashlib
import json
import os
import pathlib
import platform
import resource
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import time

MAGIC = b"GPKH2\0\0\0"
VERSION = 1
HEADER = struct.Struct("<8sIIQQ")
SEGMENT = struct.Struct("<QQQ")
INDEX_COUNT = struct.Struct("<I")
FILE_PREFIX = struct.Struct("<IQI")
LAYOUTS = [
    ("raw", 0, None),
    ("per-asset", 1, None),
    ("chunk-256k", 2, 256 * 1024),
    ("chunk-1m", 2, 1024 * 1024),
    ("chunk-4m", 2, 4 * 1024 * 1024),
]
MAX_FILES = 1_000_000
MAX_FILE_SIZE = 8 * 1024**3
READERS = 4
LEVEL = 3

zstd = ctypes.CDLL("libzstd.so.1")
zstd.ZSTD_versionNumber.argtypes = []
zstd.ZSTD_versionNumber.restype = ctypes.c_uint
zstd.ZSTD_compressBound.argtypes = [ctypes.c_size_t]
zstd.ZSTD_compressBound.restype = ctypes.c_size_t
zstd.ZSTD_compress.argtypes = [
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.c_int,
]
zstd.ZSTD_compress.restype = ctypes.c_size_t
zstd.ZSTD_decompress.argtypes = [
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.c_void_p,
    ctypes.c_size_t,
]
zstd.ZSTD_decompress.restype = ctypes.c_size_t
zstd.ZSTD_isError.argtypes = [ctypes.c_size_t]
zstd.ZSTD_isError.restype = ctypes.c_uint
zstd.ZSTD_getErrorName.argtypes = [ctypes.c_size_t]
zstd.ZSTD_getErrorName.restype = ctypes.c_char_p


def zstd_check(code: int) -> int:
    if zstd.ZSTD_isError(code):
        raise RuntimeError(zstd.ZSTD_getErrorName(code).decode("utf-8"))
    return code


def zstd_compress(data: bytes) -> bytes:
    bound = zstd.ZSTD_compressBound(len(data))
    dst = ctypes.create_string_buffer(max(1, bound))
    src = ctypes.create_string_buffer(data, len(data)) if data else ctypes.create_string_buffer(1)
    written = zstd_check(zstd.ZSTD_compress(dst, bound, src, len(data), LEVEL))
    return ctypes.string_at(dst, written)


def zstd_decompress(data: bytes, expected_size: int) -> bytes:
    dst = ctypes.create_string_buffer(max(1, expected_size))
    src = ctypes.create_string_buffer(data, len(data)) if data else ctypes.create_string_buffer(1)
    written = zstd_check(zstd.ZSTD_decompress(dst, expected_size, src, len(data)))
    if written != expected_size:
        raise ValueError(f"frame decoded to {written} bytes; expected {expected_size}")
    return ctypes.string_at(dst, written) if written else b""


def regular_files(root: pathlib.Path) -> list[pathlib.Path]:
    return sorted(
        (path for path in root.rglob("*") if path.is_file() and not path.is_symlink()),
        key=lambda path: path.relative_to(root).as_posix(),
    )


def peak_rss_kib() -> int:
    return int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)


def pack_archive(
    input_root: pathlib.Path, output_path: pathlib.Path, layout_name: str, chunk_size: int | None
) -> dict:
    layout_code = next(code for name, code, size in LAYOUTS if name == layout_name)
    files = regular_files(input_root)
    if len(files) > MAX_FILES:
        raise ValueError("input contains too many files")
    input_bytes = sum(path.stat().st_size for path in files)
    records = []
    payload_bytes = 0
    framing_bytes = HEADER.size
    index_bytes = INDEX_COUNT.size
    started = time.perf_counter()

    with output_path.open("wb") as archive:
        archive.write(b"\0" * HEADER.size)
        for path in files:
            rel_path = path.relative_to(input_root).as_posix()
            path_bytes = rel_path.encode("utf-8")
            file_size = path.stat().st_size
            if file_size > MAX_FILE_SIZE:
                raise ValueError(f"input file exceeds limit: {rel_path}")
            segments = []

            if layout_name == "raw":
                offset = archive.tell()
                stored = 0
                with path.open("rb") as source:
                    while block := source.read(1024 * 1024):
                        archive.write(block)
                        stored += len(block)
                segments.append((offset, stored, file_size))
            elif layout_name == "per-asset":
                raw = path.read_bytes()
                encoded = zstd_compress(raw)
                offset = archive.tell()
                archive.write(encoded)
                segments.append((offset, len(encoded), len(raw)))
            else:
                assert chunk_size is not None
                with path.open("rb") as source:
                    while raw := source.read(chunk_size):
                        encoded = zstd_compress(raw)
                        offset = archive.tell()
                        archive.write(encoded)
                        segments.append((offset, len(encoded), len(raw)))

            records.append(
                {"path": rel_path, "path_bytes": path_bytes, "size": file_size, "segments": segments}
            )
            index_bytes += FILE_PREFIX.size + len(path_bytes)
            framing_bytes += SEGMENT.size * len(segments)
            payload_bytes += sum(segment[1] for segment in segments)

        index_offset = archive.tell()
        archive.write(INDEX_COUNT.pack(len(records)))
        for record in records:
            archive.write(
                FILE_PREFIX.pack(len(record["path_bytes"]), record["size"], len(record["segments"]))
            )
            archive.write(record["path_bytes"])
            for segment in record["segments"]:
                archive.write(SEGMENT.pack(*segment))
        archive.seek(0)
        archive.write(HEADER.pack(MAGIC, VERSION, layout_code, len(records), index_offset))
        archive.flush()
    elapsed = time.perf_counter() - started
    archive_size = output_path.stat().st_size
    if archive_size != payload_bytes + index_bytes + framing_bytes:
        raise AssertionError("archive size does not match payload/index/framing accounting")
    return {
        "layout": layout_name,
        "input_files": len(files),
        "input_bytes": input_bytes,
        "archive_bytes": archive_size,
        "payload_bytes": payload_bytes,
        "index_bytes": index_bytes,
        "framing_bytes": framing_bytes,
        "compression_ratio": input_bytes / payload_bytes if payload_bytes else 1.0,
        "pack_seconds": elapsed,
        "pack_mib_s": input_bytes / (1024 * 1024) / elapsed if elapsed else 0.0,
        "pack_peak_rss_kib": peak_rss_kib(),
        "archive_sha256": hashlib.sha256(output_path.read_bytes()).hexdigest(),
    }


def parse_archive(archive_path: pathlib.Path) -> tuple[dict, list[dict]]:
    file_size = archive_path.stat().st_size
    if file_size < HEADER.size:
        raise ValueError("archive is shorter than its header")
    with archive_path.open("rb") as archive:
        header = archive.read(HEADER.size)
        magic, version, layout_code, count, index_offset = HEADER.unpack(header)
        if magic != MAGIC or version != VERSION or layout_code not in {0, 1, 2}:
            raise ValueError("unsupported archive header")
        if count > MAX_FILES:
            raise ValueError("archive file count exceeds limit")
        if index_offset < HEADER.size or index_offset > file_size - INDEX_COUNT.size:
            raise ValueError("index offset is out of range")
        archive.seek(index_offset)
        index = archive.read(file_size - index_offset)

    cursor = 0

    def take(size: int) -> bytes:
        nonlocal cursor
        if size < 0 or cursor + size > len(index):
            raise ValueError("truncated archive index")
        part = index[cursor : cursor + size]
        cursor += size
        return part

    actual_count = INDEX_COUNT.unpack(take(INDEX_COUNT.size))[0]
    if actual_count != count:
        raise ValueError("header and index file counts differ")
    records = []
    seen_paths = set()
    for _ in range(count):
        path_len, asset_size, segment_count = FILE_PREFIX.unpack(take(FILE_PREFIX.size))
        if path_len == 0 or path_len > 1024 * 1024 or asset_size > MAX_FILE_SIZE:
            raise ValueError("invalid file metadata size")
        path_bytes = take(path_len)
        rel_path = path_bytes.decode("utf-8")
        normalized = pathlib.PurePosixPath(rel_path)
        if (
            rel_path in seen_paths
            or normalized.is_absolute()
            or "\\" in rel_path
            or any(part in {"", ".", ".."} for part in normalized.parts)
        ):
            raise ValueError("unsafe or duplicate asset path")
        seen_paths.add(rel_path)
        if segment_count > 1_000_000:
            raise ValueError("segment count exceeds limit")
        segments = []
        uncompressed_total = 0
        for _ in range(segment_count):
            offset, compressed_size, uncompressed_size = SEGMENT.unpack(take(SEGMENT.size))
            if (
                offset < HEADER.size
                or offset > index_offset
                or compressed_size > index_offset - offset
                or uncompressed_size > asset_size - uncompressed_total
            ):
                raise ValueError("segment range is out of bounds")
            segments.append((offset, compressed_size, uncompressed_size))
            uncompressed_total += uncompressed_size
        if uncompressed_total != asset_size:
            raise ValueError("segment sizes do not match asset size")
        records.append({"path": rel_path, "size": asset_size, "segments": segments})
    if cursor != len(index):
        raise ValueError("unexpected trailing index bytes")
    return {"layout_code": layout_code, "index_offset": index_offset}, records


def lookup_archive(
    archive_path: pathlib.Path, input_root: pathlib.Path, readers: int = READERS
) -> dict:
    header, records = parse_archive(archive_path)
    fd = os.open(archive_path, os.O_RDONLY)

    def read_one(record: dict) -> tuple[int, float, int]:
        started = time.perf_counter()
        output = bytearray(record["size"])
        max_segment_working = 0
        cursor = 0
        for offset, compressed_size, uncompressed_size in record["segments"]:
            encoded = os.pread(fd, compressed_size, offset)
            if len(encoded) != compressed_size:
                raise ValueError("short payload read")
            temporary_bytes = (
                compressed_size
                if header["layout_code"] == 0
                else compressed_size + uncompressed_size
            )
            max_segment_working = max(max_segment_working, temporary_bytes)
            decoded = encoded if header["layout_code"] == 0 else zstd_decompress(encoded, uncompressed_size)
            output[cursor : cursor + uncompressed_size] = decoded
            cursor += uncompressed_size
        expected = (input_root / pathlib.PurePosixPath(record["path"])).read_bytes()
        if output != expected:
            raise ValueError(f"source-byte mismatch for {record['path']}")
        return record["size"], time.perf_counter() - started, record["size"] + max_segment_working

    started = time.perf_counter()
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=readers) as executor:
            results = list(executor.map(read_one, records))
    finally:
        os.close(fd)
    elapsed = time.perf_counter() - started
    latencies = [result[1] for result in results]
    byte_count = sum(result[0] for result in results)
    return {
        "all_assets_match_source": True,
        "files_read": len(records),
        "bytes_read": byte_count,
        "reader_threads": readers,
        "full_read_seconds": elapsed,
        "full_read_mib_s": byte_count / (1024 * 1024) / elapsed if elapsed else 0.0,
        "full_read_latency_p50_ms": percentile(latencies, 0.50) * 1000,
        "full_read_latency_p95_ms": percentile(latencies, 0.95) * 1000,
        "full_read_latency_p99_ms": percentile(latencies, 0.99) * 1000,
        "max_single_read_working_set_bytes": max((result[2] for result in results), default=0),
        "read_peak_rss_kib": peak_rss_kib(),
    }


def percentile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int((len(ordered) - 1) * q + 0.5)))
    return ordered[index]


def worker() -> None:
    command = sys.argv[1]
    if command == "pack":
        result = pack_archive(
            pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), sys.argv[4],
            None if sys.argv[5] == "-" else int(sys.argv[5]),
        )
    elif command == "read":
        result = lookup_archive(pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]))
    elif command == "parse":
        parse_archive(pathlib.Path(sys.argv[2]))
        result = {"accepted": True}
    else:
        raise ValueError(f"unknown worker command: {command}")
    print(json.dumps(result, sort_keys=True))


def generated_file(path: pathlib.Path, size: int, seed: bytes, repeated: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if repeated:
        block = hashlib.shake_256(seed).digest(4096)
        with path.open("wb") as output:
            remaining = size
            while remaining:
                part = block[: min(remaining, len(block))]
                output.write(part)
                remaining -= len(part)
        return
    with path.open("wb") as output:
        remaining = size
        counter = 0
        while remaining:
            block_seed = seed + counter.to_bytes(8, "little")
            block = hashlib.shake_256(block_seed).digest(min(1024 * 1024, remaining))
            output.write(block)
            remaining -= len(block)
            counter += 1


def create_inputs(root: pathlib.Path, real_root: pathlib.Path) -> dict[str, pathlib.Path]:
    seed = b"gpack-h2-v1"
    small = root / "generated-small"
    compressible = root / "generated-compressible"
    high_entropy = root / "generated-high-entropy"
    for number in range(512):
        generated_file(small / f"asset-{number:04d}.bin", 4096, seed + b"-small", True)
    for number in range(2):
        name = f"asset-{number:02d}.bin"
        generated_file(
            compressible / name,
            32 * 1024 * 1024,
            seed + b"-compressible-" + name.encode(),
            True,
        )
        generated_file(
            high_entropy / name,
            32 * 1024 * 1024,
            seed + b"-high-entropy-" + name.encode(),
            False,
        )

    mixed = root / "mixed"
    mixed.mkdir()
    shutil.copytree(real_root, mixed / "real")
    shutil.copytree(small, mixed / "generated-small")
    shutil.copytree(compressible, mixed / "generated-compressible")
    shutil.copytree(high_entropy, mixed / "generated-high-entropy")
    return {
        "godot-real": real_root,
        "many-small": small,
        "large-compressible": compressible,
        "large-high-entropy": high_entropy,
        "mixed": mixed,
    }


def run_worker(arguments: list[str]) -> dict:
    process = subprocess.run(
        [sys.executable, str(pathlib.Path(__file__).resolve()), *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(process.stdout)


def median_range(values: list[float]) -> dict:
    return {"median": statistics.median(values), "min": min(values), "max": max(values)}


def malformed_archive_checks(archive: pathlib.Path, scratch: pathlib.Path) -> dict:
    truncated = scratch / "truncated.gpkh2"
    with archive.open("rb") as source, truncated.open("wb") as target:
        target.write(source.read(max(0, archive.stat().st_size - 1)))
    truncated_result = subprocess.run(
        [sys.executable, str(pathlib.Path(__file__).resolve()), "parse", str(truncated)],
        capture_output=True,
        text=True,
    )

    out_of_range = scratch / "out-of-range.gpkh2"
    shutil.copyfile(archive, out_of_range)
    with out_of_range.open("r+b") as bad:
        header = bad.read(HEADER.size)
        _, _, _, _, index_offset = HEADER.unpack(header)
        bad.seek(index_offset + INDEX_COUNT.size)
        path_len, _, segment_count = FILE_PREFIX.unpack(bad.read(FILE_PREFIX.size))
        if segment_count == 0:
            raise AssertionError("malformed range fixture requires a nonempty frame")
        segment_offset = index_offset + INDEX_COUNT.size + FILE_PREFIX.size + path_len
        bad.seek(segment_offset)
        bad.write(struct.pack("<Q", index_offset + 1))
    range_result = subprocess.run(
        [sys.executable, str(pathlib.Path(__file__).resolve()), "parse", str(out_of_range)],
        capture_output=True,
        text=True,
    )
    return {
        "truncated_rejected": truncated_result.returncode != 0,
        "out_of_range_rejected": range_result.returncode != 0,
    }


def run_benchmark() -> None:
    real_root = pathlib.Path(sys.argv[2]).resolve()
    output_path = pathlib.Path(sys.argv[3]).resolve()
    output_path.mkdir(parents=True, exist_ok=True)
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="gpack-h2-"))
    workloads = create_inputs(scratch / "inputs", real_root)
    workload_sizes = {
        name: sum(path.stat().st_size for path in regular_files(root))
        for name, root in workloads.items()
    }
    observations = []
    deterministic_hashes = {}
    malformed_result = None
    def command_version(command: list[str]) -> str:
        try:
            completed = subprocess.run(command, capture_output=True, text=True, check=False)
            return (completed.stdout or completed.stderr).strip().splitlines()[0]
        except (OSError, IndexError):
            return "unavailable"

    memory_bytes = None
    if hasattr(os, "sysconf"):
        try:
            memory_bytes = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
        except (ValueError, OSError):
            pass
    storage = subprocess.run(
        ["df", "-T", str(scratch)], capture_output=True, text=True, check=False
    ).stdout.strip()

    for run_number in range(5):
        rotated = LAYOUTS[run_number:] + LAYOUTS[:run_number]
        for workload_name, input_root in workloads.items():
            for layout_name, _, chunk_size in rotated:
                archive = scratch / f"{workload_name}-{layout_name}-run{run_number + 1}.gpkh2"
                pack = run_worker(
                    ["pack", str(input_root), str(archive), layout_name,
                     "-" if chunk_size is None else str(chunk_size)]
                )
                read = run_worker(["read", str(archive), str(input_root)])
                if not read["all_assets_match_source"]:
                    raise AssertionError(f"correctness gate failed: {workload_name}/{layout_name}")
                key = f"{workload_name}/{layout_name}"
                prior = deterministic_hashes.setdefault(key, pack["archive_sha256"])
                if prior != pack["archive_sha256"]:
                    raise AssertionError(f"deterministic output gate failed: {key}")
                observation = {
                    "workload": workload_name,
                    "layout": layout_name,
                    "run": run_number + 1,
                    **pack,
                    **read,
                }
                observations.append(observation)
                if workload_name == "godot-real" and layout_name == "per-asset" and run_number == 0:
                    malformed_result = malformed_archive_checks(archive, scratch)
                    if not all(malformed_result.values()):
                        raise AssertionError("malformed archive rejection gate failed")
                archive.unlink()

    grouped = {}
    for workload_name in workloads:
        grouped[workload_name] = {}
        for layout_name, _, _ in LAYOUTS:
            rows = [
                row for row in observations
                if row["workload"] == workload_name and row["layout"] == layout_name
            ]
            grouped[workload_name][layout_name] = {
                "runs": rows,
                "archive_bytes": median_range([row["archive_bytes"] for row in rows]),
                "payload_bytes": median_range([row["payload_bytes"] for row in rows]),
                "index_bytes": median_range([row["index_bytes"] for row in rows]),
                "framing_bytes": median_range([row["framing_bytes"] for row in rows]),
                "compression_ratio": median_range([row["compression_ratio"] for row in rows]),
                "pack_mib_s": median_range([row["pack_mib_s"] for row in rows]),
                "pack_peak_rss_kib": median_range([row["pack_peak_rss_kib"] for row in rows]),
                "full_read_seconds": median_range([row["full_read_seconds"] for row in rows]),
                "full_read_mib_s": median_range([row["full_read_mib_s"] for row in rows]),
                "full_read_latency_p50_ms": median_range([row["full_read_latency_p50_ms"] for row in rows]),
                "full_read_latency_p95_ms": median_range([row["full_read_latency_p95_ms"] for row in rows]),
                "full_read_latency_p99_ms": median_range([row["full_read_latency_p99_ms"] for row in rows]),
                "max_single_read_working_set_bytes": median_range(
                    [row["max_single_read_working_set_bytes"] for row in rows]
                ),
                "read_peak_rss_kib": median_range([row["read_peak_rss_kib"] for row in rows]),
                "all_assets_match_source": all(row["all_assets_match_source"] for row in rows),
                "deterministic_archive_bytes": len(set(row["archive_sha256"] for row in rows)) == 1,
            }

    result = {
        "experiment": "H2 whole-asset framing and processing granularity",
        "status": "complete",
        "codec": {"name": "Zstandard", "version_number": int(zstd.ZSTD_versionNumber()), "level": LEVEL},
        "machine": {
            "platform": platform.platform(),
            "uname": list(platform.uname()),
            "processor": platform.processor() or "not reported",
            "logical_cpu_count": os.cpu_count(),
            "physical_memory_bytes": memory_bytes,
            "python": sys.version,
            "zstd_cli": command_version(["zstd", "--version"]),
            "goose_cli": command_version([str(pathlib.Path("goose-bin/goose").resolve()), "--version"]),
            "storage_and_filesystem": storage,
        },
        "reader_threads": READERS,
        "workload_bytes": workload_sizes,
        "layouts": [name for name, _, _ in LAYOUTS],
        "paired_runs_per_configuration": 5,
        "correctness_gate": all(
            row["all_assets_match_source"] for row in observations
        ),
        "deterministic_output_gate": all(
            len({row["archive_sha256"] for row in observations
                 if row["workload"] == workload and row["layout"] == layout}) == 1
            for workload in workloads for layout, _, _ in LAYOUTS
        ),
        "malformed_archive_checks": malformed_result,
        "workloads": grouped,
        "observations": observations,
    }
    (output_path / "results.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"results": str(output_path / "results.json"),
                      "scratch": str(scratch),
                      "gates": {"correctness": result["correctness_gate"],
                                "determinism": result["deterministic_output_gate"],
                                "malformed": malformed_result}}, sort_keys=True))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in {"pack", "read", "parse"}:
        worker()
    elif len(sys.argv) > 1 and sys.argv[1] == "bench":
        run_benchmark()
    else:
        raise SystemExit(
            "usage: harness.py bench REAL_CORPUS_ROOT OUTPUT_DIR | "
            "harness.py pack INPUT_ROOT ARCHIVE LAYOUT CHUNK_BYTES_OR_DASH | "
            "harness.py read ARCHIVE INPUT_ROOT | harness.py parse ARCHIVE"
        )
