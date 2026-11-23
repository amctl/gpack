# Product v1 runtime throughput results

Status: executed; throughput and malformed-input gates passed for this Linux
build. Full per-run measurements and archive hashes are in [results.json](results.json).

## Results

| Workload | Reader | Throughput MiB/s, median [range] | p50 ms, median [range] | p95 ms, median [range] | Peak RSS KiB, median [range] |
|---|---|---:|---:|---:|---:|
| Godot real | Goose | 178.0 [157.4, 220.1] | 0.016 [0.009, 0.021] | 0.184 [0.142, 0.227] | 3,712 [3,644, 3,888] |
| Godot real | C reference | 166.5 [146.9, 181.7] | 0.017 [0.009, 0.020] | 0.250 [0.183, 1.609] | 4,200 [4,016, 4,472] |
| Mixed | Goose | 1,286.4 [1,213.1, 1,368.6] | 0.0092 [0.0086, 0.0096] | 0.0114 [0.0097, 0.0152] | 133,888 [133,868, 133,948] |
| Mixed | C reference | 1,379.0 [1,318.0, 1,422.0] | 0.0083 [0.0081, 0.0084] | 0.0093 [0.0088, 0.0099] | 198,532 [198,404, 198,648] |

Median paired Goose/C throughput ratios were 1.212 [0.938, 1.330] on Godot
real and 0.920 [0.914, 0.962] on mixed. Comparing the five-run throughput
medians, Goose is 6.9% faster on Godot-real and 6.7% slower on mixed, within
the 10% requirement. The paired Godot-real ratio range is wide, but its median
and the throughput medians remain above the gate.

The mixed workload contains 579 files and 137,512,216 source bytes, including
the 32 MiB assets at the default per-asset limit. Goose peak RSS was about
131 MiB, versus about 194 MiB for C. The actual archive SHA-256 values and
source counts/bytes are in the JSON artifact.

The Godot-real archive contains 63 files / 1,197,336 source bytes and has SHA-256
`bc62d2c34dc6437b50f4f87940b40b402873c441cb856c75ef8e756e0db689ad`. The mixed
archive has SHA-256
`89c9a93357468d3c1e9035abb302668e95d66b11fa09d2e417dc645328ec381a`.

Both readers rejected all four malformed archive cases: truncated header,
truncated index, index CRC mismatch, and corrupted compressed payload/frame.
Every timed asset read matched its source-manifest CRC; the Goose reader also
performed its product content CRC check.

## Hot-path changes

The Goose CRC32 update now uses one 256-entry byte-table lookup per input byte
instead of two 16-entry nibble-table lookups. For compressed payloads stored
in at most 1 MiB, the reader now reads the frame into one bounded buffer and
uses a native one-shot Zstandard decode. That call first checks that the
compressed extent is exactly one frame, applies the same maximum-window
setting as the streaming path, and requires the decoded size to match. Larger
frames retain the streaming path. The existing CRC check remains after either
decode path.

## Decision and limits

The runtime throughput requirement is met for the measured v1 workloads on
this Linux host, so issue 22's performance gate is accepted for this build.
This does not close issue 23: the production CMake linkage, other platforms,
and cross-platform correctness remain unverified. Treat the timing as a local
benchmark result rather than a cross-platform performance guarantee.
