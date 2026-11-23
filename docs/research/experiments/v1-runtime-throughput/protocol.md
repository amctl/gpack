# Product v1 runtime throughput protocol

Status: executed; the five-pair median throughput gate passed on one Linux host.
Results: [results.md](results.md), with raw observations in [results.json](results.json).

## Comparison

- The Goose executable imports the product `reader::open`, `reader::request`,
  and `reader::read_request` APIs. Four long-lived Goose workers process the
  deterministic path order through bounded typed queues.
- The C reference parses the same v1 archive, resolves the same sorted source
  manifest, and uses four pthread workers with positional reads and Zstandard
  1.5.7. Both implementations use a byte-table IEEE CRC32 and validate decoded
  bytes against the source manifest CRC.
- The product CLI creates each archive once. Both readers consume that exact
  file, whose SHA-256 is recorded per workload. Five pairs alternate execution
  order: Goose/C, C/Goose, Goose/C, C/Goose, Goose/C.
- `godot-real` is the pinned 2D, 3D, and audio demo corpus. `mixed` adds 512
  deterministic 4 KiB files, two 32 MiB compressible files, and two 32 MiB
  high-entropy files. The default 32 MiB reader cap and four-reader default are
  used without an override.
- `/usr/bin/time` records process peak RSS. Per-asset p50/p95 latency covers
  the complete read, decompression when used, and content CRC verification.
  Parse time is reported separately from the timed lookup phase.

## Correctness and malformed input

Before timing, the C and Goose readers must accept each product archive and
report the exact source file count and byte total. Every returned asset is
checked against its source CRC, and the product reader checks the archive CRC.
Both readers are also required to reject a truncated header, truncated index,
index CRC mismatch, and corrupted compressed payload/frame.

## Reproduction environment

The measurements used Goose v2026.4 and the vendored Zstandard 1.5.7 source.
The archive packer and Goose runtime were linked to the static 1.5.7 library;
the C reference was linked to that same static archive. CMake is absent in the
environment, so the Goose build was compiled and then linked with the static
archive directly instead of using the repository CMake wrapper. This measures
the product source and pinned codec, but does not validate the production
CMake build path. The full command, host data, version number, archive hashes,
and every run are captured in `results.json`.

The experiment is warm-cache, local-storage Linux evidence. It does not claim
macOS/Windows performance or cold-storage behavior.
