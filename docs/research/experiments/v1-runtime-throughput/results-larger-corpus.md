# Expanded real-project runtime results

Status: supplementary five-pair run completed on one Linux host with the
production CMake-linked GPack build. Raw observations and environment details
are in [results-larger-corpus.json](results-larger-corpus.json).

## Workloads

| Workload | Files | Source bytes | GPack archive bytes | One pack run (s) |
|---|---:|---:|---:|---:|
| Existing Godot real | 63 | 1,197,336 | 1,118,384 | 0.019 |
| Existing mixed | 579 | 137,512,216 | 70,375,233 | 0.584 |
| Godot Material Testers | 109 | 133,365,708 | 114,083,027 | 0.859 |

Material Testers is the pinned `3d/material_testers` project from the Godot
4.7 demo release. Its input archive SHA-256 is
`f84524261ec5c1012af6e66f5304861f4f1afa0eef78daf71f2791897397ad87`; the
extracted path/size/SHA-256 manifest is
[here](../godot-4.7-corpus/material-testers-manifest.json). The largest asset
is `backgrounds/park.hdr` at 29,029,087 bytes, below the default 32 MiB
per-asset limit. GPack's output archive SHA-256 is
`44c9adf8fd7d25e6a078d0a8e82c4b4f0a1883011077dcec0896b1c5ca64d028`.

## Reader results

Throughput and RSS are medians with observed min–max ranges across five paired
runs. Each pair alternated Goose/C execution order.

| Workload | Goose throughput MiB/s | C throughput MiB/s | Paired Goose/C median [range] | Goose peak RSS KiB | C peak RSS KiB |
|---|---:|---:|---:|---:|---:|
| Existing Godot real | 265.7 [183.2, 526.9] | 328.6 [257.7, 388.3] | 0.808 [0.558, 1.357] | 3,764 [3,508, 4,068] | 4,272 [3,824, 4,348] |
| Existing mixed | 1,217.7 [1,169.2, 1,314.0] | 1,255.4 [1,232.6, 1,289.0] | 0.979 [0.907, 1.066] | 133,940 [133,880, 134,372] | 198,828 [198,724, 198,984] |
| Godot Material Testers | 1,046.8 [987.2, 1,078.1] | 1,103.5 [1,062.3, 1,135.7] | 0.970 [0.869, 0.985] | 106,684 [106,676, 107,108] | 170,544 [167,436, 170,864] |

On Material Testers, the median paired throughput ratio is within the existing
10% gate, and Goose's median peak RSS is about 37% below the C reader. The
large project therefore adds evidence about a 127 MiB, 109-file real input and
four concurrent full-asset readers under the default limit. It does not prove
that the same throughput or memory result holds for other games, hosts, cache
states, or platforms.

The repeated small `godot-real` workload had a wide paired ratio range and a
0.808 median in this run, unlike the original acceptance run. Its total read
volume is only about 1.14 MiB, so several milliseconds of run-to-run scheduling
variation has a large effect on the ratio. Treat the original issue 22 result
as its recorded acceptance run; this supplementary rerun demonstrates why the
small workload alone is a weak basis for broad performance claims. The mixed
workload remained within 10% by the median paired ratio.

## Method and limits

The GPack CLI and Goose runtime used the production CMake path with Goose
v2026.4 and static Zstandard 1.5.7; the C reference used that same static
Zstandard archive. The runtime used four workers and the default 32 MiB asset
limit. Full archive open/manifest preparation happened before timed reads;
each timed read included decode and CRC verification. The script checked
source counts/bytes and CRCs, ran reader preflight on every workload, and
recorded malformed rejection on the existing small real archive.

This is warm-cache, local-storage Linux evidence from an Intel Core Ultra 7
255H host with 32 GiB RAM. Peak RSS is process-level and workload-specific.
Packing time is a single observation per workload, not a paired estimate. The
run does not cover macOS or Windows, cold storage, a user's complete shipped
game, or a general memory/performance guarantee.
