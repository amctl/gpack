# Run H1 queue payload cost experiment

Type: task
Status: resolved
Blocked by: 14

## Question

Execute the preregistered H1 comparison using the verified corpus manifest and
the harness developed for H2/H3 where applicable. Preserve correctness and
deterministic-output hard gates, five paired measured runs per configuration,
machine/toolchain records, and a separate result artifact under
`docs/research/experiments/h1-queue-payload-cost/`. Summarize whether H1 meets
its predeclared decision rule and update the research synthesis without
treating inconclusive results as support.

## Answer

Ran five paired measurements for four workloads, four chunk sizes, and worker
counts 1, 2, 4, and 16, comparing full compressed payloads through Goose result
queues, metadata queues with per-chunk native-file staging, and a serial
baseline. All 720 archives independently decompressed to their source chunks;
repeated builds and all three pipelines were byte-identical within each
configuration.

The metadata path met the predeclared gain/cost rule in five large
high-entropy configurations: 64 KiB at four workers, and all four chunk sizes
at sixteen workers. The sixteen-worker large high-entropy cases improved median
throughput by 15.0–22.7% and reduced peak RSS by 19.6–44.8% versus the
full-payload queue. No configuration qualified on the real Godot corpus or the
large compressible control. Four many-small configurations crossed the
threshold, but do not establish the large-payload mechanism. H1 is supported
for large, poorly compressible chunks under higher concurrency; staging is not
justified as a general default.

The full medians, ranges, paired measurements, and limits are in
[`results.md`](../../../docs/research/experiments/h1-queue-payload-cost/results.md)
and [`results.json`](../../../docs/research/experiments/h1-queue-payload-cost/results.json).
Issue 16 is now unblocked to measure indexed runtime lookup.
