# H3 runtime lookup follow-up protocol

Status: executed; correctness gates passed, 10% throughput-gap gate failed.
Results: [results.md](results.md), with per-run data in [results.json](results.json).

## Hypothesis

A narrow native positional-read boundary can serve complete indexed assets to
concurrent Goose runtime callers without moving archive validation and lookup
policy out of Goose or causing unbounded per-reader memory growth.

## Comparison

- Goose policy and validation using native positional reads and decompression.
- A minimal C reference reader using the same H2 per-asset-frame archive.
- Four concurrent readers, each performing complete-asset reads in a fixed,
  deterministic query order.

Use the pinned corpus manifest, H2 archive bytes, Zstandard 1.5.7, and identical
storage. Collect five paired runs for the real and mixed workloads.

## Metrics and hard gates

- Whole-asset throughput, p50/p95 latency, and peak RSS.
- Byte equality against source assets and cross-reader archive compatibility.
- Reject truncated indexes, out-of-range offsets, malformed paths, and invalid
  frame bounds before returning data.
- Report reader ABI functions, Goose/C source split, and validation overhead.

Consider the native boundary worthwhile only if it preserves correctness and
malformed-input rejection, stays within a 10% median throughput gap from C, and
has bounded working memory per configured reader. Report material results with
five-run medians and ranges; this follow-up alone does not freeze a product
format or codec.
