# Measure native-backed indexed runtime lookup

Type: task
Status: resolved
Blocked by: 15

## Question

Complete the runtime half of H3 after H1. Use the H2 indexed archive structure
with equivalent Goose/native and C reference readers. Measure whole-asset lookup
throughput and latency on the verified Godot corpus and mixed workload, with
four concurrent readers and five paired runs. Preserve correctness, malformed
range rejection, and deterministic archive compatibility as hard gates. Record
the reader ABI surface, lookup working memory, and validation overhead in a
separate result artifact under `docs/research/experiments/h3-runtime-lookup/`.
Does the native boundary retain the pack-side gains while meeting the Goose
runtime lookup contract?

## Answer

Correctness and malformed-input rejection passed for both the Goose/native and
C reference readers, but the Goose runtime missed the preregistered 10%
throughput-gap gate: median throughput was 27.4% below C on the real corpus and
12.1% below C on mixed. The narrow native ABI is viable for positional I/O and
Zstandard, with parsing and path lookup retained in Goose; this prototype is
not ready to freeze as the product runtime. Reduce queue/allocation overhead
and define a practical per-reader memory budget before repeating the benchmark.
See [H3 runtime results](../../../docs/research/experiments/h3-runtime-lookup/results.md).
