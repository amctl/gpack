# H2 results — whole-asset framing and processing granularity

Status: complete. The preregistered H2 protocol was executed with five paired runs per workload/layout. The full observation set and metric ranges are in [`results.json`](results.json); the experimental encoder/reader is [`harness.py`](harness.py).

## Environment and controls

- Codec: Zstandard 1.5.7, level 3; four-reader thread pool. Goose CLI was recorded but not used by this H2 prototype.
- Machine: Linux-7.3.4-300.fc45.x86_64-x86_64-with-glibc2.44; 16 logical CPUs; 30.7 GiB RAM.
- Runtime: Python 3.15.2 with native `libzstd`; temporary storage: tmpfs mounted at `/tmp`.
- Storage is `/tmp` tmpfs. These results characterize framing and codec work with memory-backed storage; they do not measure local SSD/HDD behavior.
- Workload sizes: `godot-real` 1,197,336 bytes; `large-compressible` 67,108,864 bytes; `large-high-entropy` 67,108,864 bytes; `many-small` 2,097,152 bytes; `mixed` 137,512,216 bytes.
- Generated controls use seed `gpack-h2-v1`; the verified Godot project ZIP hashes and per-file manifest are in [`../godot-4.7-corpus/manifest.json`](../godot-4.7-corpus/manifest.json).

## Hard gates

- Source-byte correctness for every returned asset: **passed**.
- Byte-identical rebuilds across five runs for every workload/layout: **passed**.
- Truncated and out-of-range archive metadata rejected before reads: **passed**.
- All archive component counts reconcile exactly: payload + index + framing = archive size.

## Results

Values are medians over five runs; bracketed ranges are the observed min–max. Index bytes cover asset paths and file-level records. Framing bytes cover the fixed archive header and one descriptor per stored frame/chunk. Payload bytes include the Zstandard frame streams.

| Workload | Layout | Archive MiB | Payload / index / framing KiB | Ratio | Pack MiB/s | Build RSS MiB | Full-read MiB/s | Per-asset p95 ms | Max single-read working set MiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| godot-real | chunk-1m | 1.067 [1.067–1.067] | 1087/3/1 | 1.075 [1.075–1.075] | 160.0 [146.7–180.0] | 25.8 [25.7–25.9] | 47.0 [43.9–54.4] | 3.7 [2.9–4.7] | 2.00 [2.00–2.00] |
| godot-real | chunk-256k | 1.067 [1.067–1.067] | 1087/3/2 | 1.075 [1.075–1.075] | 170.4 [166.9–175.3] | 24.4 [24.4–24.4] | 56.4 [52.8–77.4] | 2.4 [2.2–3.3] | 1.17 [1.17–1.17] |
| godot-real | chunk-4m | 1.067 [1.067–1.067] | 1087/3/1 | 1.075 [1.075–1.075] | 166.8 [164.4–173.8] | 25.9 [25.9–26.0] | 57.3 [39.1–58.6] | 3.0 [2.4–4.3] | 2.00 [2.00–2.00] |
| godot-real | per-asset | 1.067 [1.067–1.067] | 1087/3/2 | 1.075 [1.075–1.075] | 158.2 [153.4–167.4] | 25.4 [25.4–25.5] | 50.0 [42.4–62.0] | 3.5 [2.5–4.3] | 2.00 [2.00–2.00] |
| godot-real | raw | 1.147 [1.147–1.147] | 1169/3/2 | 1.000 [1.000–1.000] | 481.6 [468.4–499.2] | 24.1 [24.1–24.1] | 91.4 [74.4–110.3] | 1.6 [1.3–1.8] | 1.34 [1.34–1.34] |
| large-compressible | chunk-1m | 0.258 [0.258–0.258] | 263/0/2 | 249.364 [249.364–249.364] | 1654.8 [1572.5–1907.2] | 27.0 [26.9–27.0] | 492.8 [429.0–717.2] | 122.2 [80.4–133.7] | 33.00 [33.00–33.00] |
| large-compressible | chunk-256k | 1.015 [1.015–1.015] | 1033/0/6 | 63.427 [63.427–63.427] | 1773.7 [1735.6–2039.3] | 24.1 [24.1–24.1] | 566.8 [453.6–628.1] | 106.3 [89.1–133.3] | 32.25 [32.25–32.25] |
| large-compressible | chunk-4m | 0.069 [0.069–0.069] | 70/0/0 | 933.312 [933.312–933.312] | 1163.0 [992.5–1189.1] | 38.2 [38.1–38.3] | 349.3 [323.3–378.5] | 165.6 [154.1–172.6] | 36.00 [36.00–36.00] |
| large-compressible | per-asset | 0.014 [0.014–0.014] | 14/0/0 | 4672.018 [4672.018–4672.018] | 540.4 [496.5–697.6] | 119.1 [119.1–119.2] | 322.1 [242.7–523.5] | 190.5 [109.8–250.7] | 64.01 [64.01–64.01] |
| large-compressible | raw | 64.000 [64.000–64.000] | 65536/0/0 | 1.000 [1.000–1.000] | 1438.8 [1373.2–1511.4] | 24.1 [24.1–24.1] | 499.1 [388.9–800.5] | 118.4 [61.1–130.6] | 64.00 [64.00–64.00] |
| large-high-entropy | chunk-1m | 64.004 [64.004–64.004] | 65538/0/2 | 1.000 [1.000–1.000] | 990.9 [767.8–1346.1] | 28.0 [27.9–28.1] | 399.3 [377.7–482.1] | 140.9 [124.9–150.6] | 34.00 [34.00–34.00] |
| large-high-entropy | chunk-256k | 64.010 [64.010–64.010] | 65540/0/6 | 1.000 [1.000–1.000] | 1247.4 [1020.0–1556.7] | 24.2 [24.1–24.3] | 464.4 [396.2–805.3] | 121.4 [74.9–155.9] | 32.50 [32.50–32.50] |
| large-high-entropy | chunk-4m | 64.002 [64.002–64.002] | 65538/0/0 | 1.000 [1.000–1.000] | 631.8 [576.1–806.0] | 42.1 [42.0–42.1] | 301.9 [269.6–505.6] | 196.2 [113.2–210.8] | 40.00 [40.00–40.00] |
| large-high-entropy | per-asset | 64.002 [64.002–64.002] | 65538/0/0 | 1.000 [1.000–1.000] | 337.1 [295.1–432.4] | 183.2 [183.1–183.3] | 269.4 [247.7–331.0] | 225.6 [160.9–245.9] | 96.00 [96.00–96.00] |
| large-high-entropy | raw | 64.000 [64.000–64.000] | 65536/0/0 | 1.000 [1.000–1.000] | 1544.0 [1342.4–2340.5] | 24.1 [24.1–24.1] | 494.0 [425.5–678.6] | 119.0 [87.5–137.2] | 64.00 [64.00–64.00] |
| many-small | chunk-1m | 2.031 [2.031–2.031] | 2053/15/12 | 0.998 [0.998–0.998] | 135.6 [132.7–145.0] | 24.1 [24.1–24.1] | 21.7 [17.3–26.8] | 1.3 [1.0–1.6] | 0.01 [0.01–0.01] |
| many-small | chunk-256k | 2.031 [2.031–2.031] | 2053/15/12 | 0.998 [0.998–0.998] | 135.2 [131.6–144.9] | 24.1 [24.1–24.1] | 21.6 [17.7–23.5] | 1.4 [1.1–1.6] | 0.01 [0.01–0.01] |
| many-small | chunk-4m | 2.031 [2.031–2.031] | 2053/15/12 | 0.998 [0.998–0.998] | 137.7 [136.8–141.3] | 24.1 [24.1–24.1] | 21.9 [16.7–26.9] | 1.3 [1.0–1.7] | 0.01 [0.01–0.01] |
| many-small | per-asset | 2.031 [2.031–2.031] | 2053/15/12 | 0.998 [0.998–0.998] | 145.0 [140.4–149.5] | 24.1 [24.1–24.1] | 22.1 [21.1–26.5] | 1.3 [1.2–1.4] | 0.01 [0.01–0.01] |
| many-small | raw | 2.026 [2.026–2.026] | 2048/15/12 | 1.000 [1.000–1.000] | 232.2 [230.5–239.7] | 24.1 [24.1–24.1] | 30.5 [22.9–39.2] | 0.9 [0.7–1.1] | 0.01 [0.01–0.01] |
| mixed | chunk-1m | 67.368 [67.368–67.368] | 68941/27/16 | 1.948 [1.948–1.948] | 1051.4 [1031.8–1072.4] | 28.6 [28.6–28.6] | 346.3 [317.1–372.9] | 1.9 [1.5–2.1] | 34.00 [34.00–34.00] |
| mixed | chunk-256k | 68.131 [68.131–68.131] | 69713/27/26 | 1.926 [1.926–1.926] | 1109.8 [1086.0–1415.8] | 25.2 [25.1–25.3] | 365.1 [325.9–384.2] | 1.8 [1.5–1.9] | 32.50 [32.50–32.50] |
| mixed | chunk-4m | 67.177 [67.177–67.177] | 68748/27/14 | 1.953 [1.953–1.953] | 789.0 [703.4–862.3] | 42.6 [42.5–42.6] | 295.5 [254.7–424.8] | 1.8 [1.8–3.3] | 40.00 [40.00–40.00] |
| mixed | per-asset | 67.121 [67.121–67.121] | 68692/27/14 | 1.955 [1.955–1.955] | 361.8 [346.9–372.4] | 183.8 [183.5–184.0] | 200.2 [186.6–308.4] | 1.8 [1.7–2.1] | 96.00 [96.00–96.00] |
| mixed | raw | 131.181 [131.181–131.181] | 134289/27/14 | 1.000 [1.000–1.000] | 1381.2 [1310.9–1434.3] | 24.4 [24.4–24.5] | 356.6 [325.0–432.5] | 1.1 [0.8–1.1] | 64.00 [64.00–64.00] |

## Predeclared material-gain rule

Compare each chunk size with per-asset frames within the same workload. A material gain is at least 10% higher median pack throughput or at least 20% lower median build RSS, with at least four of five paired runs moving in that direction. Chunking is eligible only when median archive size and full-read time are each no more than 5% worse.

| Workload | Chunk size | Archive delta | Pack throughput delta | Pack runs faster | RSS reduction | RSS runs lower | Full-read time delta | Meets chunk rule |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| godot-real | 256k | -0.00% | +7.7% | 5/5 | +3.9% | 5/5 | -11.3% | no |
| godot-real | 1m | -0.01% | +1.1% | 4/5 | -1.3% | 0/5 | +6.4% | no |
| godot-real | 4m | -0.01% | +5.5% | 4/5 | -1.9% | 0/5 | -12.8% | no |
| large-compressible | 256k | 7237.87% | +228.2% | 5/5 | +79.8% | 5/5 | -43.2% | no |
| large-compressible | 1m | 1766.71% | +206.2% | 5/5 | +77.4% | 5/5 | -34.6% | no |
| large-compressible | 4m | 399.03% | +115.2% | 5/5 | +67.9% | 5/5 | -7.8% | no |
| large-high-entropy | 256k | 0.01% | +270.1% | 5/5 | +86.8% | 5/5 | -42.0% | yes |
| large-high-entropy | 1m | 0.00% | +194.0% | 5/5 | +84.7% | 5/5 | -32.5% | yes |
| large-high-entropy | 4m | 0.00% | +87.4% | 5/5 | +77.0% | 5/5 | -10.8% | yes |
| many-small | 256k | 0.00% | -6.7% | 0/5 | +0.0% | 0/5 | +2.6% | no |
| many-small | 1m | 0.00% | -6.5% | 0/5 | +0.0% | 0/5 | +2.0% | no |
| many-small | 4m | 0.00% | -5.1% | 0/5 | +0.0% | 0/5 | +1.0% | no |
| mixed | 256k | 1.50% | +206.8% | 5/5 | +86.3% | 5/5 | -45.2% | yes |
| mixed | 1m | 0.37% | +190.6% | 5/5 | +84.5% | 5/5 | -42.2% | yes |
| mixed | 4m | 0.08% | +118.1% | 5/5 | +76.8% | 5/5 | -32.2% | yes |

## Interpretation

The full H2 tradeoff hypothesis is inconclusive for choosing a default: per-asset frames did not show a material archive-size or full-read advantage on the real Godot corpus, and the many-small control showed no measurable framing difference. The large-file half of the hypothesis is supported on the generated controls. Fixed chunks meet the material-gain and 5% cost rules for high-entropy and mixed workloads. On the mixed workload, all chunk sizes reduced median build RSS by 76.8–86.3%, improved pack throughput by 118–207%, and improved aggregate full-read throughput by 32–45%; archive size increased by 0.08–1.50%.

The large repeated-content control is the counterexample: resetting the Zstandard frame at each chunk increased archive size by 399–7,238% versus one whole-asset frame. Its build-memory and throughput gains do not meet the archive-size gate. The real Godot corpus and many-small-file control show no material chunking gain; their layouts are within roughly 0.01% of one another in archive size.

The data supports evaluating a chunked option for large high-entropy assets, but leaves the default unresolved; H3/H1 results and the real workload mix remain relevant before locking architecture defaults. The 256 KiB option had the strongest mixed-workload speed and RSS gains but the largest size penalty; 1 MiB was a middle point; 4 MiB had the smallest size penalty and weaker, still-material gains.

## Limits

The harness is a Python prototype that calls `libzstd` directly; it is not Goose or gpack. `/tmp` is tmpfs, so storage latency and writeback costs are absent. `ru_maxrss` includes the interpreter and native allocations. The selected real corpus totals only about 1.2 MB, while large-file behavior comes from deterministic generated controls. Treat performance values as relative results for this machine and harness, not cross-platform product estimates.
