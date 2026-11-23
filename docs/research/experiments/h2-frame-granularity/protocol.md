# H2 protocol — whole-asset framing and processing granularity

Status: preregistration finalized 2026-11-23 and executed. Results are in
[`results.md`](results.md) and [`results.json`](results.json). No architecture
default was selected by this experiment.

## Hypothesis

One independent frame per asset will reduce metadata and simplify lookup when
the runtime reads complete assets. Fixed-size chunks may lower build-side
working memory or improve packing throughput for very large assets, but add
index/framing overhead and require the runtime to reassemble the complete asset.
The value of chunking for this v1 contract is therefore a build and full-read
tradeoff, not partial-range latency.

## Comparison

- One independent compressed frame per file.
- Fixed-size chunks within each file, initially 256 KiB, 1 MiB, and 4 MiB,
  reassembled for each runtime read.
- Raw storage with the same index as a lower-bound overhead baseline.

## Controls and workloads

Use identical normalized paths, payload bytes, codec version/level, metadata
policy, and deterministic ordering. Use Zstandard 1.5.7 at level 3 as the fixed
comparison codec for this experiment; this does not decide the product codec.
Evaluate the pinned real corpus, deterministic generated controls, and their
mixed union. The real corpus is one eligible pinned Godot
4.7 demo each from 2D, 3D, and audio, selected after recording release hashes,
inventorying the unpacked trees, and reviewing project and embedded third-party
notices. Include each project's regular files and retain its notices. Add
these deterministic controls: 512 4 KiB files made from a repeated 4 KiB
SHAKE-256 block; two 32 MiB files made from a repeated path-seeded 4 KiB block;
and two 32 MiB high-entropy files from SHAKE-256(path || counter). Use seed
`gpack-h2-v1`; the mixed corpus contains all three generated classes and the
real corpus. The real projects supply already-compressed media. Collect five
paired measured runs per configuration in a fixed, rotated layout order and
report the median and spread.

## Metrics

- Total archive size split into payload, index, and framing overhead.
- Pack throughput and peak memory during build.
- Full-asset lookup throughput and latency, including concurrent independent
  reads; time to verify the full archive and maximum working set for one read.
- Compression ratio per workload class.

## Decision rule

Support the tradeoff hypothesis if per-asset frames reduce overhead and full
read cost on typical assets while fixed chunks improve build memory or
throughput on large assets, with all output-size and runtime costs reported.
Treat a gain as material when the median improves by at least 10% in throughput
or at least 20% in peak RSS, with at least four of five paired runs moving in
the same direction. Choose chunks only when they meet a material threshold and
their median archive-size and full-read costs are each no more than 5% worse;
otherwise choose the simpler per-asset layout. Smaller or inconsistent
differences are inconclusive. Apply correctness and deterministic-output hard
gates to every configuration.

## Sanity checks

Every returned asset must match its source bytes, including assets spanning
multiple chunks. Exercise concurrent independent reads. Reject truncated and
out-of-range metadata before allocation. Repeat builds byte-identically.
