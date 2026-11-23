# Run H3 Goose/native boundary experiment

Type: task
Status: resolved
Blocked by: 13

## Question

Execute the preregistered H3 comparison using the verified corpus manifest and
the harness developed for H2 where applicable. Preserve correctness and
deterministic-output hard gates, five paired measured runs per configuration,
machine/toolchain records, and a separate result artifact under
`docs/research/experiments/h3-native-streaming-boundary/`. Summarize whether H3
meets its predeclared decision rule and update the research synthesis without
treating inconclusive results as support.

## Answer

Executed five paired runs across the five H2 workloads for Goose whole-file,
Goose policy with a C streaming backend, and a minimal C reference. The
independent parser verified all source bytes; all repeated and cross-method
archives were byte-identical. Short-I/O, injected write-failure cleanup, and
malformed-count checks passed. The native Goose path met the pack-side gain
rule on all large workloads: median peak RSS fell 92.2–95.6% and median pack
throughput rose 117–137% versus Goose whole-file processing. Median native
throughput was not more than 10% below the C reference.

At the time of this pack-side result, the sequential benchmark envelope did
not test indexed positional reads, concurrent runtime lookup, extraction
throughput, or production-format validation. Issue 16 later measured runtime
reads, passed correctness, and missed its throughput gate; see the comment
below. The exact pack harness, measurements, and limitations are in
[`results.md`](../../../docs/research/experiments/h3-native-streaming-boundary/results.md)
and [`results.json`](../../../docs/research/experiments/h3-native-streaming-boundary/results.json).
After H1, issue 16 tracks the missing runtime lookup comparison.

## Comments

- Issue 16 completed the runtime follow-up: source-byte and malformed-input
  gates passed, but Goose throughput missed the preregistered target. The
  runtime implementation is not yet performance-accepted; see
  [`h3-runtime-lookup/results.md`](../../../docs/research/experiments/h3-runtime-lookup/results.md).
