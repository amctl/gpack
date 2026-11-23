# gpack v1 product specification

Status: implementation in progress; build foundation, v1 format primitives,
and the raw pack/read slice are implemented.

## Product contract

gpack is a build-time CLI and a Goose runtime library for packaging game and
runtime assets in a separately distributable, read-only archive. V1 creates a
new, versioned gpack format. It targets Goose desktop builds on Linux, macOS,
and Windows. Packing accepts a directory tree of regular files and produces a
deterministic archive; runtime callers open that archive and read a complete
asset by normalized path without extracting the archive.

The application replaces the complete archive outside gpack. V1 does not mount
the archive or provide partial archive updates.

## User-facing surface

```text
gpack pack INPUT_DIR OUTPUT.gpk
gpack list ARCHIVE.gpk
gpack verify ARCHIVE.gpk
```

- `pack` walks the input tree recursively, rejects symlinks and other
  non-regular entries, normalizes and sorts asset paths, and writes an archive.
  It fails if it detects source mutation during the build. The caller must
  keep the input tree stable while packing.
- `list` validates the header and complete index, then prints canonical paths
  and stored/uncompressed sizes. It does not decode payloads.
- `verify` validates metadata and reads every asset, checking the stored
  content CRC32 and any Zstandard frame checksum.
- The runtime library exposes archive open/close and complete-asset read by
  path. Reads use positional I/O and may run concurrently on one open archive.

V1 does not include unpack/extract commands, byte-range reads, stable asset
IDs, cross-file deduplication, compression dictionaries, incremental updates,
legacy import/export, or filesystem mounting.

## Asset path contract

An asset path is a valid UTF-8, relative path with `/` separators. Reject
absolute paths, NUL, backslashes, empty components, `.` and `..` components,
and duplicate canonical path bytes. Convert platform separators to `/` while
scanning. Preserve Unicode code points and letter case; lookups are
case-sensitive. Sort path bytes lexicographically for deterministic output.
Paths are identifiers inside the archive; v1 does not extract them to a host
filesystem.

## Integrity, compression, and reproducibility

- Pin Goose v2026.4 and vendored Zstandard 1.5.7 source.
- Compress each non-empty asset independently with Zstandard level 3. Enable
  its frame content checksum and store the uncompressed size.
- If the complete Zstandard frame is not smaller than the source, store the
  asset raw and record codec `raw`; otherwise record codec `zstd`.
- Store IEEE CRC32 of the uncompressed bytes for every asset. Store IEEE CRC32
  for the header and index as specified in [format v1](../format/v1.md).
- Checksums detect accidental corruption. They do not authenticate an archive
  or protect against maliciously chosen content.
- For identical input path and file bytes, options, and exact pinned codec
  build, gpack promises identical archive bytes. Cross-build identity across
  Linux, macOS, and Windows is not promised until golden-output checks pass on
  each target.

The underlying codec and native-build evidence is in the
[codec source review](../research/wayfinder-codec-options.md).

The archive has no source timestamps or permissions. Reserved fields are zero.
Entries are ordered by canonical path bytes, and payloads follow that same
order. The writer stages output in a temporary file beside the destination,
flushes it, and atomically replaces the destination only after final metadata
and checksums are complete.

## Runtime limits and concurrency

The format permits an asset up to 8 GiB and an index up to 64 MiB, with at most
one million entries. A runtime archive defaults to a 32 MiB maximum
uncompressed asset size and four concurrent reads. Callers may raise the
per-asset limit when opening an archive. The limit bounds one read's allocation;
the application remains responsible for buffers it retains and for its total
concurrent memory budget.

The reader validates the full header and index, every path, codec, size, and
payload range before returning an asset. It rejects overlapping payload
ranges, unsupported versions/codecs, nonzero reserved fields, checksum
mismatches, and Zstandard data that is not exactly one complete frame.

## Supported builds

| Target | Compiler | Codec |
|---|---|---|
| Linux | GCC | Static, pinned Zstandard 1.5.7 |
| macOS | Apple Clang | Static, pinned Zstandard 1.5.7 |
| Windows | MSVC | Static, pinned Zstandard 1.5.7 |

Builds run natively on each target. The Goose package owns archive policy,
parsing, path indexing, and orchestration. Its native C target owns file
handles, positional reads/writes, flush/replace operations, and Zstandard calls
only. The native target must not interpret gpack headers or index records.

## Validation and release

CI runs Goose formatting/type checks, native builds, and correctness fixtures
on all three targets. Fixtures cover deterministic golden archives, raw and
Zstandard entries, round trips, CRC/frame failures, truncated/out-of-range
metadata, unsafe and duplicate paths, size limits, and concurrent reads.
Benchmarks remain manual and live under `docs/research/experiments/`; noisy
shared-runner throughput is not a release gate. Releases are cut from tags
only after the complete platform correctness matrix passes and include the
Zstandard license notices. See the [release procedure](../release.md).

## Evidence and unresolved acceptance risks

The custom format remains the selected product contract. The completed
restricted ZIP comparison found a small raw-container size advantage for
GPack and workload-dependent codec results: GPack's Zstandard/raw profile was
faster on the mixed and Material Testers workloads, while ZIP DEFLATE was
slightly smaller and used less reader RSS on Material Testers. No general
winner is established. H2 found that
per-asset framing did not materially change the real corpus. H3 pack-side
measurements support the native streaming boundary for large assets, while the
H3 runtime Goose prototype missed its 10% throughput-gap target. The product
v1 benchmark met the 10% median throughput gate on one Linux host in its
original run; a supplementary 127 MiB real project also measured within that
gate and recorded workload-specific peak RSS. A repeated run of the small real
corpus had high variability. These results do not establish general or
cross-platform performance/memory guarantees. See the [original runtime benchmark](../research/experiments/v1-runtime-throughput/results.md),
[expanded workload results](../research/experiments/v1-runtime-throughput/results-larger-corpus.md),
[research findings](../research/findings.md), [restricted ZIP comparison](../research/experiments/restricted-zip-comparison/results.md),
and [ZIP capability review](../research/zip-profile-capabilities.md),
as well as the [risk register](risks.md).
