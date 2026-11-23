# Run H2 framing and processing-granularity experiment

Type: task
Status: resolved
Blocked by: 12

## Question

Build the smallest reproducible harness needed to execute the preregistered H2
protocol using the corpus manifest from issue 12 and deterministic generated
controls. Preserve correctness and deterministic-output hard gates, five
paired measured runs per configuration, machine/toolchain records, and a
separate result artifact under `docs/research/experiments/h2-frame-granularity/`.
Summarize whether H2 meets its predeclared decision rule and update the
research synthesis without treating inconclusive results as support.

## Answer

Executed five paired runs for each of five workload classes and five layouts
using the verified Godot corpus, deterministic controls, Zstandard 1.5.7 at
level 3, and four concurrent readers. The harness, full observations, and
summary are at
[`docs/research/experiments/h2-frame-granularity/`](../../../docs/research/experiments/h2-frame-granularity/).

All correctness, deterministic-output, and malformed-archive rejection gates
passed. The preregistered material-gain and 5% cost rules were met by all chunk
sizes on the large high-entropy and mixed workloads. On the mixed workload,
chunking increased archive size by 0.08–1.50%, improved pack throughput by
118–207%, reduced median peak RSS by 76.8–86.3%, and improved full-read
throughput by 32–45%. On repetitive large inputs, chunks increased archive
size by 399–7,238%, so they failed the archive-size gate. The real corpus and
many-small control showed no material framing advantage.

The large-file part of H2 is supported, but the full hypothesis is inconclusive
for selecting a default: the actual Godot corpus did not establish a material
per-asset advantage or a representative large-file workload. All measurements
used `/tmp` tmpfs and a Python/libzstd prototype, not Goose or physical storage.
See [`results.md`](../../../docs/research/experiments/h2-frame-granularity/results.md)
for ranges, machine details, and limitations. At the time this result was
recorded, the pack-side H3 and H1 results were available and indexed runtime
lookup was queued as issue 16; its later outcome is recorded below.

## Comments

- Issue 16 subsequently measured indexed runtime lookup. Correctness passed;
  Goose missed the 10% throughput gap on both workloads. See
  [`h3-runtime-lookup/results.md`](../../../docs/research/experiments/h3-runtime-lookup/results.md).
