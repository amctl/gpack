# H3 protocol — Goose policy layer with native streaming backend

Status: preregistration finalized 2026-11-23 and executed for the pack-side
boundary comparison. The broader runtime and positional-I/O hypothesis remains
inconclusive. Results are in [`results.md`](results.md) and
[`results.json`](results.json).

## Hypothesis

A narrow C ABI for persistent file handles, positional reads/writes, codecs,
and atomic archive finalization can provide bounded-memory performance near a C
reference while leaving format policy, indexing, validation, and CLI logic in
Goose.

## Comparison

- All-Goose prototype using current `read_file` and in-memory arrays.
- Goose control/format layer with C streaming I/O and codec backend.
- Minimal C reference using identical archive format and codec settings.

Use the eligible selected Godot 4.7 projects (one each from 2D, 3D, and audio)
and the deterministic generated controls defined in H2. Pin and record the
same corpus manifest, codec, options, and output format across all three
implementations.

For this prototype, use Zstandard 1.5.7 level 3 and a sequential test envelope:
an eight-byte magic, a little-endian asset count, then sorted records containing
path length, uncompressed size, UTF-8 path, and one Zstandard frame. The frame
length is obtained from its own frame boundary. The format is only a benchmark
control, not a proposed gpack format. The Goose whole-file path uses Goose
`read_file`/`write_file_atomic` and Goose-owned envelope construction, with the
same C one-shot codec primitive needed by the current toolchain. The native path
keeps envelope policy and record ordering in Goose, while C handles positional
file reading, streaming Zstandard, and atomic output. The C reference owns the
same envelope in C. All paths consume an identical sorted manifest generated
before timing.

## Metrics

- Pack and extract throughput; peak resident memory.
- Full-asset lookup throughput/latency with concurrent readers; archive size;
  validation overhead.
- Number and size of ABI functions; Goose/C source split; duplicated policy.
- Malformed input handling and deterministic archive equality.
- Collect five measured runs per configuration; report the median and spread.

## Decision rule

Compare five paired runs per configuration. Consider native streaming
worthwhile only if it yields at least 20% lower median peak RSS or at least 10%
higher median throughput than the all-Goose path on the large-asset controls,
with at least four of five paired runs moving in the same direction. It must
also keep memory bounded by configured in-flight work, remain within a 10%
median throughput gap from the C reference on large assets, keep format policy
in Goose, and reject malformed inputs at least as strictly as the reference.
The 10% reference gap is an engineering target, not a statistical claim.
Smaller or inconsistent gains do not justify the native boundary by
themselves.

## Sanity checks

Use the same compiler optimization, native library versions, and storage. Verify
all outputs through an independent parser or reference reader; exercise short
reads/writes and injected I/O failures; repeat builds for byte equality.
