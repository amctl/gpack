# H1 results — Goose queue payload cost

Status: complete. The queue-copy hypothesis is supported for large
high-entropy workloads at higher worker counts; it is not a general
recommendation for the real corpus or compressible inputs.

## Setup and gates

- Goose v2026.4; cc (GCC) 16.2.1 20261029 (Red Hat 16.2.1-3); Zstandard 1.5.7 level 3.
- OS: Linux-7.3.4-300.fc45.x86_64-x86_64-with-glibc2.44; 16 logical CPUs; 30.7 GiB RAM; storage: tmpfs mounted at /tmp.
- Four workloads (real Godot, many-small, large compressible, large high-entropy), four chunk sizes (64 KiB, 256 KiB, 1 MiB, 4 MiB), worker counts 1/2/4/16, and five measured runs per configuration.
- Result queues held at most two messages per worker. Source files were split before timing; compression, result transfer/staging, and ordered archive assembly were timed.
- Independent decompression and source-byte checks, repeat determinism, and byte equality across payload/stage/serial variants: **passed for every configuration**.

## Decision-rule summary

A metadata-staging configuration qualifies when it improves median throughput by at least 10% or reduces peak RSS by at least 20%, with at least four of five paired runs moving the same way, and neither other primary metric regresses by more than 5%.

| Workload | Qualifying stage configurations |
|---|---:|
| godot-real | 0/16 |
| large-compressible | 0/16 |
| large-high-entropy | 5/16 |
| many-small | 4/16 |

Only large high-entropy controls produced qualifying results at larger worker counts. All four chunk sizes qualified at 16 workers; 64 KiB also qualified at 4 workers. Four many-small configurations crossed the numeric threshold, but the real Godot and large-compressible workloads had no qualifying configuration. Treat many-small gains as workload-specific; they do not establish a large-payload queue cost.

## Large high-entropy results at 16 workers

| Chunk size | Full-payload throughput MiB/s | Staged throughput MiB/s | Throughput change | Full-payload RSS MiB | Staged RSS MiB | RSS reduction | Paired direction |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 64 KiB | 740.1 | 908.0 | +22.7% | 30.4 | 17.0 | 44.2% | faster 5/5; lower RSS 5/5 |
| 256 KiB | 780.3 | 904.4 | +15.9% | 75.6 | 41.8 | 44.8% | faster 5/5; lower RSS 5/5 |
| 1024 KiB | 688.9 | 844.1 | +22.5% | 145.8 | 100.8 | 30.9% | faster 5/5; lower RSS 5/5 |
| 4096 KiB | 557.5 | 641.0 | +15.0% | 252.0 | 202.6 | 19.6% | faster 4/5; lower RSS 5/5 |

Across all 64 payload/stage comparisons, nine configurations met the numerical gain and cost rule: five large high-entropy configurations and four many-small configurations. For high-entropy payloads, staging reduced the configured result-queue payload capacity from as much as 151 MB (about 144 MiB; two messages per worker × 16 workers × a 4 MiB chunk plus compression bound) to small metadata messages. Process RSS still includes each worker's raw and compressed buffers: at 4 MiB/16 workers, peak RSS remained about 203 MiB after staging, versus 252 MiB with full payloads.

## Interpretation

H1 is supported in the large high-entropy/high-worker region: staging met the predeclared material-gain rule at 64 KiB/4-worker and at all four chunk sizes with 16 workers. The effect is not general. Compression made large repetitive assets small before they crossed the queue, and the actual Godot corpus showed no qualifying staging benefit. This evidence supports bounding queue bytes or staging large, poorly compressible results when concurrency and chunk size are high; it does not justify staging every asset by default.

The serial baseline and complete medians/ranges for every workload, worker count, and chunk size are in [`results.json`](results.json). Archive construction, validation, and source-byte equality use the H1 benchmark envelope, not a product-format implementation.

## Limits

- Linux x86_64 and `/tmp` tmpfs only; no physical storage or cross-platform measurement.
- Staging uses one temporary file per compressed chunk through Goose native file functions. Filesystem costs on SSD/HDD may change the balance.
- Input splitting is outside timing. Read, compression, queue/staging, and assembly are measured together; per-stage CPU time is not separated.
- The metadata queue is count-bounded at two messages per worker; worker-local raw and codec buffers still scale with workers × chunk size.
- The verified corpus is small; generated large controls determine most of the queue-payload effect.
