# H1 protocol — queue payload cost

Status: preregistration for a future implementation experiment. No experiment
has run.

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

## Workloads and independent variables

- Corpus: many small files; few large compressible files; few large
  incompressible/already-compressed files; mixed corpus.
- Chunk size: 64 KiB, 256 KiB, 1 MiB, 4 MiB.
- Worker count: 1, 2, 4, and available-core count, capped to avoid machine
  oversubscription.
- Keep codec level, source order, output format, and storage device fixed.

## Metrics

- End-to-end input MiB/s and wall time.
- Peak resident memory and maximum in-flight payload bytes.
- Time in read, hash, compress, queue/stage, ordered write.
- Output bytes and byte-for-byte deterministic repeat output.

## Decision rule

H1 is supported if the full-payload path has a repeatable throughput regression
or materially higher peak memory at larger chunks/worker counts, while metadata
staging keeps memory bounded and preserves output bytes. Report exact effect
sizes and do not treat a small noisy difference as support.

## Sanity checks

- All variants produce archives that verify and extract to byte-identical
  inputs.
- Repeat identical runs and compare archive bytes.
- Confirm the instrumentation includes native allocations and Goose stacks.
- Record the CPU, OS, compiler, codec version/build options, corpus checksums,
  and storage medium.
