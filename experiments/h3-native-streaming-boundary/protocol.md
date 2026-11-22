# H3 protocol — Goose policy layer with native streaming backend

Status: preregistration for a future implementation experiment. No experiment
has run.

## Hypothesis

A narrow C ABI for persistent file handles, positional reads/writes, codecs,
and atomic archive finalization can provide bounded-memory performance near a C
reference while leaving format policy, indexing, validation, and CLI logic in
Goose.

## Comparison

- All-Goose prototype using current `read_file` and in-memory arrays.
- Goose control/format layer with C streaming I/O and codec backend.
- Minimal C reference using identical archive format and codec settings.

## Metrics

- Pack and extract throughput; peak resident memory.
- Random lookup latency; archive size; validation overhead.
- Number and size of ABI functions; Goose/C source split; duplicated policy.
- Malformed input handling and deterministic archive equality.

## Decision rule

Support if the mixed implementation has memory bounded by configured in-flight
work, has no more than a 10% throughput gap from the C reference on large
assets, and keeps format policy in Goose without weaker malformed-input
rejection. Treat the 10% margin as a proposed engineering target, not a
statistical claim.

## Sanity checks

Use the same compiler optimization, native library versions, and storage. Verify
all outputs through an independent parser or reference reader; exercise short
reads/writes and injected I/O failures; repeat builds for byte equality.
