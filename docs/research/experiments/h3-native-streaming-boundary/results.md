# H3 results — Goose/native streaming boundary

Status: complete for the preregistered pack-side comparison. The indexed
runtime follow-up was measured separately and missed its throughput gate; see
[H3 runtime results](../h3-runtime-lookup/results.md).

## Setup and hard gates

- Goose: v2026.4; C compiler: `cc (GCC) 16.2.1 20261029 (Red Hat 16.2.1-3)`.
- Zstandard 1.5.7, level 3; storage: tmpfs mounted at /tmp.
- Five paired runs for each of five workloads and three implementations; all used one sorted manifest and the same sequential benchmark envelope.
- Independent frame parsing and source-byte verification: **passed**.
- Byte-identical repeated builds and cross-implementation archive equality: **passed**.
- Short-I/O output equality, cleanup after injected write failures, and malformed count rejection: **passed**.

## Measurements

Medians and observed min–max ranges across five runs. Throughput uses input bytes; RSS is the child process peak.

| Workload | Implementation | Input MiB | Archive MiB | Pack MiB/s median [min–max] | Peak RSS MiB median [min–max] |
|---|---|---:|---:|---:|---:|
| godot-real | c-reference | 1.14 | 1.065 | 87.7 [74.0–195.9] | 4.13 [4.06–4.16] |
| godot-real | goose-all | 1.14 | 1.065 | 103.1 [51.7–150.3] | 7.14 [6.82–7.16] |
| godot-real | goose-native | 1.14 | 1.065 | 87.9 [63.8–200.6] | 4.75 [4.44–4.75] |
| large-compressible | c-reference | 64.00 | 0.014 | 1537.7 [1203.6–2710.0] | 5.32 [5.24–5.42] |
| large-compressible | goose-all | 64.00 | 0.014 | 793.0 [573.0–840.9] | 73.85 [73.62–73.88] |
| large-compressible | goose-native | 64.00 | 0.014 | 1721.6 [1193.1–2732.1] | 5.76 [5.66–5.96] |
| large-high-entropy | c-reference | 64.00 | 64.002 | 921.1 [680.7–1214.5] | 5.54 [5.53–5.75] |
| large-high-entropy | goose-all | 64.00 | 64.002 | 432.5 [403.9–470.0] | 137.95 [137.80–138.02] |
| large-high-entropy | goose-native | 64.00 | 64.002 | 989.0 [784.2–1199.3] | 6.23 [5.89–6.24] |
| many-small | c-reference | 2.00 | 2.018 | 130.2 [108.2–259.4] | 2.13 [2.13–2.36] |
| many-small | goose-all | 2.00 | 2.018 | 163.8 [111.7–188.2] | 5.05 [4.82–5.07] |
| many-small | goose-native | 2.00 | 2.018 | 143.4 [94.5–232.9] | 2.73 [2.63–2.82] |
| mixed | c-reference | 131.14 | 67.106 | 1492.0 [1426.1–1944.8] | 5.71 [5.69–5.71] |
| mixed | goose-all | 131.14 | 67.106 | 636.4 [598.8–690.6] | 141.23 [141.08–141.43] |
| mixed | goose-native | 131.14 | 67.106 | 1510.0 [1374.7–1836.9] | 6.28 [6.23–6.42] |

## Predeclared decision rule

Native is worthwhile over the Goose whole-file baseline if it lowers median peak RSS by at least 20% or raises median throughput by at least 10% on the large controls, with at least four of five paired runs moving the same way. The native path must not be more than 10% slower than C on a large workload.

| Large workload | Native pack throughput vs Goose all-file | Native RSS reduction | Paired runs faster / RSS ≥20% lower | Native throughput vs C | Rule result |
|---|---:|---:|---:|---:|---|
| large-compressible | +117.1% | 92.2% | 5/5 / 5/5 | +12.0% | pass |
| large-high-entropy | +128.7% | 95.5% | 5/5 / 5/5 | +7.4% | pass |
| mixed | +137.3% | 95.6% | 5/5 / 5/5 | +1.2% | pass |

The measured pack-side boundary meets the gain/cost rule on all three large workloads. Native peak RSS was about 5.8–6.3 MiB across 64–131 MiB workloads, compared with 73.9–141.3 MiB for Goose whole-file processing. Native throughput was not more than 10% below the C reference by median on any large workload. The output archive bytes matched exactly across all three implementations.

## Interpretation

The pack-side evidence supports a narrow Goose-to-C streaming boundary for large assets: the Goose whole-file path scales its working set with asset size, while the native path remained near a fixed process-and-buffer footprint and improved median large-workload throughput. The native Goose path also preserved Goose ownership of ordering and record framing; its FFI surface has six functions.

This pack-side benchmark envelope is sequential and has no index, so it does
not itself measure positional archive lookup, concurrent runtime reads,
extraction throughput, or production-format validation. The separate [H3
runtime study](../h3-runtime-lookup/results.md) measures indexed concurrent
reads and records that Goose missed its throughput gate. These are boundary
prototypes, not gpack. The C reference and native backend share the same
Zstandard streaming implementation, which controls codec behavior but makes
their codec comparison intentionally uninformative.

## Limits

- Linux x86_64 and `/tmp` tmpfs only; no physical storage or cross-platform run.
- Single-threaded pack path with 128 KiB read/write buffers; bounded-memory behavior is measured for this configuration only.
- Short reads and writes were forced to 13 and 17 bytes; an injected output failure verified temporary-file cleanup. Read-failure injection was not implemented.
- The independent Python reader verified every asset but was not included in throughput or RSS comparisons.
- The synthetic controls and small Godot corpus do not establish the product workload mix.
