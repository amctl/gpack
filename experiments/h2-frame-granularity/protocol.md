# H2 protocol — compression and access granularity

Status: preregistration for a future implementation experiment. No experiment
has run.

## Hypothesis

Independent whole-file frames will reduce per-entry metadata and simplify
indexing for many small assets, while fixed-size frames will improve partial
read latency for large assets; there is no single granularity that dominates
both workloads.

## Comparison

- One independent compressed frame per file.
- Fixed-size chunks within each file, initially 256 KiB, 1 MiB, and 4 MiB.
- Raw storage with the same index as a lower-bound overhead baseline.

## Controls and workloads

Use identical normalized paths, payload bytes, codec version/level, metadata
policy, and deterministic ordering. Evaluate a many-small-file corpus, a few
large files, and a mixed corpus. Include compressed media and repetitive text.

## Metrics

- Total archive size split into payload, index, and framing overhead.
- Full extraction throughput and random 4 KiB / 64 KiB range read latency.
- Time to verify the full archive and maximum working set for one lookup.
- Compression ratio per workload class.

## Decision rule

Support the tradeoff hypothesis if whole-file framing yields smaller overhead
for many small files while fixed chunks improve range-read latency on large
assets, with output ratio and costs reported. Choose a default only after
declaring the intended workload weighting.

## Sanity checks

Every returned range must match source bytes; test first/last bytes and ranges
crossing frame boundaries. Reject out-of-range and truncated metadata before
allocation. Repeat builds byte-identically.
