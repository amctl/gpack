# Meet the runtime throughput acceptance gate

Type: task
Status: resolved
Blocked by: 20, 21, 16

## Goal

Profile the production-shaped Goose reader, reduce dispatch/allocation costs,
and repeat the H3 paired benchmark with correctness and memory checks.

## Acceptance

- Five paired runs use byte-identical product v1 archives, corpus, and a C
  reference reader on the Godot-real and mixed workloads. Preserve the H3
  workload/order/measurement method where it remains applicable.
- Goose median throughput is no more than 10% below C on both workloads, or
  the product requirement is explicitly revised before release.
- Correctness, malformed-input rejection, p50/p95 latency, and peak RSS are
  reported with ranges; the four-reader/32 MiB defaults are remeasured.
- If the gate still fails, record a design decision and keep the product claim
  explicit that runtime performance is unaccepted.

## Outcome

The product-shaped five-pair benchmark is in
`docs/research/experiments/v1-runtime-throughput/`. Goose median throughput was
6.9% above C on Godot-real and 6.7% below C on mixed, meeting the 10% gate.
The C and Goose readers consumed the same product v1 archive bytes for each
workload. Source CRCs and malformed-input checks passed. The four-reader and
32 MiB defaults were measured; Goose median peak RSS was 3,712 KiB on
Godot-real and 133,888 KiB on mixed.

The measured build used Goose v2026.4 and statically linked vendored Zstandard
1.5.7. It bypassed the repository's CMake wrapper because CMake is unavailable
on this host. The benchmark passes issue 22 for this Linux build; production
CMake linkage and other supported platforms remain issue 23 work.
