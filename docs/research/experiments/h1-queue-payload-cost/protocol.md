# H1 protocol — queue payload cost

Status: preregistration finalized and executed 2026-11-23. Results are in
[`results.md`](results.md) and [`results.json`](results.json); the evidence
supports staging selectively for large, poorly compressible payloads under
higher concurrency, not as a general default.

## Hypothesis

Sending whole compressed chunk arrays as Goose typed queue results will raise
peak memory and reduce throughput as chunk size and worker count increase,
compared with a pipeline that stages payload bytes outside the Goose queue and
queues only small metadata.

## Mechanism

Goose queue elements are copied flat values. The queue's configured limit is a
message count, so a fixed number of messages does not bound their total byte
size. Ordered result collection may also retain completed large chunks while
waiting for an earlier slow chunk.

## Comparison

1. Queue full payload: `{sequence, sizes, codec, digest, payload[]}`.
2. Metadata queue: `{sequence, temp-file-or-native-handle, sizes, codec,
   digest}`; a native staging backend owns payload bytes until the ordered
   writer consumes them.
3. Single-thread baseline with the same format and codec.

Use Zstandard 1.5.7 level 3 for every path. Pre-split source assets into fixed
chunk files before timing so workers receive small path/sequence jobs rather
than copying raw source chunks through a second queue. The full-payload path
returns compressed byte arrays through a Goose result queue. The staging path
writes each compressed result to a unique temporary file before returning only
sequence and size metadata. Both result queues are limited to two messages per
worker; producers retry refused puts, and the main program drains results while
workers run. After all chunks finish, an ordered writer assembles the same
deterministic benchmark archive from staged frames. The serial baseline uses
the same read, codec, staging, and output format without threads or queues.
Archive assembly and staging I/O are included in elapsed time; Python corpus
generation and chunk splitting are excluded. The staging backend uses Goose's
native file functions, which write to the selected storage medium.

## Workloads and independent variables

- Corpus: the eligible selected Godot 4.7 demo projects (one 2D, one 3D, one
  audio project, chosen after release-tree inventory and notice review), plus
  deterministic generated controls for many-small-file, few-large
  compressible-file, and few-large incompressible/already-compressed cases.
- Chunk size: 64 KiB, 256 KiB, 1 MiB, 4 MiB.
- Worker count: 1, 2, 4, and available-core count, capped to avoid machine
  oversubscription; this host exposes 16 logical workers.
- Keep codec level, source order, output format, and storage device fixed.
- Collect five measured runs per configuration; report the median and spread.

## Metrics

- End-to-end input MiB/s and wall time.
- Peak resident memory and maximum in-flight payload bytes.
- Time in read, hash, compress, queue/stage, ordered write.
- Output bytes and byte-for-byte deterministic repeat output.

## Decision rule

Compare each pipeline over five paired runs per configuration. A gain is
material when its median is at least 10% better in throughput or at least 20%
lower in peak RSS, and at least four of five paired runs move in the same
direction. Adopt metadata staging only if it meets one of those thresholds at
larger chunks/worker counts without a greater than 5% median regression in the
other primary metric. H1 is supported if full-payload queues cross a material
regression threshold and staging avoids it. Report exact effect sizes; smaller
or inconsistent differences are inconclusive, not support.

## Sanity checks

- All variants produce archives that verify and extract to byte-identical
  inputs.
- Repeat identical runs and compare archive bytes; correctness and byte-for-byte
  determinism are hard gates for every compared pipeline.
- Confirm the instrumentation includes native allocations and Goose stacks.
- Record the CPU, OS, compiler, codec version/build options, corpus checksums,
  and storage medium.
