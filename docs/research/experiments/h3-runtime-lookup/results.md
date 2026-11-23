# H3 indexed runtime lookup results

Status: executed, performance gate not met. The indexed runtime reader preserves
correctness and malformed-input rejection, but Goose throughput is more than
10% below the C reference on both measured workloads.

## Method

The H2 v1 per-asset Zstandard archive was used unchanged by the Goose/native
reader and C reference. The Goose policy layer parses the H2 header/index,
checks safe sorted paths and all payload ranges, maps query paths to jobs, and
checks CRC32 against the source manifest. Its native ABI has five operations:
open, stat size, positional read, close, and one-frame Zstandard decompression.
The C reference performs equivalent validation and lookup in C. Both use four
reader threads and the same fixed query order. Five paired runs alternated
execution order. `/usr/bin/time` collected peak RSS.

The `godot-real` workload is the pinned 2D/3D/audio corpus. `mixed` adds the H2
deterministic generated small, compressible, and high-entropy controls. H2's
independent reader compared every decoded asset to source bytes. The two readers
then checked CRC32 for every result. All five runs used the same archive bytes
per workload (SHA-256 in [`results.json`](results.json)). The compiler, host,
archive and Zstandard versions, per-run values, and ranges are recorded in that
JSON file.

## Results

| Workload | Reader | Throughput MiB/s, median [range] | p50 ms, median [range] | p95 ms, median [range] | Peak RSS KiB, median [range] | Parse seconds, median |
|---|---|---:|---:|---:|---:|---:|
| Godot real | Goose/native | 65.3 [56.8, 109.7] | 0.023 [0.018, 0.026] | 0.302 [0.198, 0.364] | 4,760 [4,592, 5,052] | 0.000147 |
| Godot real | C reference | 89.9 [71.7, 135.9] | 0.018 [0.016, 0.028] | 0.291 [0.202, 0.542] | 4,468 [4,328, 4,592] | 0.000082 |
| Mixed | Goose/native | 277.1 [255.0, 301.4] | 0.047 [0.046, 0.049] | 0.056 [0.051, 0.078] | 200,300 [199,320, 200,636] | 0.000431 |
| Mixed | C reference | 315.2 [273.1, 325.4] | 0.044 [0.042, 0.048] | 0.049 [0.046, 0.054] | 199,016 [198,760, 199,040] | 0.000265 |

Goose median throughput is 27.4% below C on the real corpus and 12.1% below C
on mixed. Both fail the preregistered maximum 10% gap. Median parser/manifest
time is sub-millisecond in each case and small relative to end-to-end lookup;
the Goose parser/manifest step is 63–80% slower in absolute time, but does not
explain the throughput gap by itself. Per-query latency is dominated by tiny assets on
these workloads; mixed p95 is 0.056 ms for Goose and 0.049 ms for C.

The largest single asset's compressed plus decoded buffers were 1,400,493
bytes for the real workload and 33,559,920 bytes for mixed. This is a per-read
working-set figure, not total memory: up to four asset reads can be active,
while the complete index and job table are retained. Observed process RSS on
mixed was about 200 MiB for both readers, largely reflecting four concurrent
large-asset buffers. The implementation caps one asset at 8 GiB, so that format
limit is finite but too permissive to serve as a practical memory budget.

## Correctness and limits

Both readers passed H2 source-byte verification and CRC32 result checks. Both
rejected a truncated index, out-of-range payload offset, unsafe path, and a
corrupted Zstandard frame. The same archive SHA-256 was consumed by both
readers for each workload. The archive writer was not rebuilt in this follow-up;
deterministic packing is covered by the preceding H2 experiment.

This is a prototype comparison on one Linux host with warm local files and
Zstandard 1.5.7. It does not measure cold storage, macOS/Windows behavior,
production API ergonomics, or a realistic distribution of runtime request
patterns. The C implementation uses a shared task counter; Goose uses typed
queues and a dictionary path index. That implementation difference is part of
the current boundary cost, not a controlled language-only comparison.

## Decision

The runtime correctness contract is feasible with a narrow native I/O and
codec ABI while Goose retains parsing and lookup policy. The current Goose path
does not meet the 10% throughput criterion. Do not count runtime H3 as a
performance win or freeze this runtime implementation as the product design.
The next prototype should reduce per-job queue and allocation overhead, then
repeat the paired benchmark; any production reader also needs an explicit
configurable memory limit below the current 8 GiB per-asset cap.
