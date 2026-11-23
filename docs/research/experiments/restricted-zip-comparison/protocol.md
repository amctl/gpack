# Restricted ZIP comparison protocol

Status: complete for the three recorded workloads and Linux host. See
[results](results.md) and all raw observations in [results.json](results.json).

## Question

Does the accepted GPack v1 implementation provide a measured product benefit
over a deliberately restricted ZIP/ZIP64 profile for the same Goose asset
workflow and input corpus?

The source review establishes that ZIP can represent streaming archive
construction and indexed complete-member lookup. It does not establish safety,
reproducibility, memory behavior, or performance for a Goose implementation.
See the [capability review](../../zip-profile-capabilities.md).

## Preregistered comparison

Use the pinned Godot 4.7 real corpus and the existing deterministic mixed
workload from the [v1 runtime benchmark](../v1-runtime-throughput/protocol.md).
Both formats must receive the same sorted paths and byte-identical source
files. Record source manifest and archive SHA-256 values.

Keep the ZIP implementation inside a research-only Goose package and
executable. Give it a small interface that mirrors the measured product
operations (`open`, `read` a complete asset by path, `close`, and pack a
directory); keep central-directory parsing, profile enforcement, and entry
indexing inside that module. Do not add ZIP selection or ZIP parsing to the
product `gpack` package or its CLI. A narrow native zlib shim may provide raw
DEFLATE, but it must be linked only by the research executable. Reuse the
existing positional file I/O and CRC helpers where doing so keeps the measured
work equivalent, and document any shared code that could bias the comparison.
This preserves the accepted product interface while allowing an isolated
adapter to answer the research question.

Implement a Goose reader and pack path for this restricted ZIP profile:

- single volume; no encryption, comments, directory entries, or prepended data;
- UTF-8 flag and normalized relative `/` paths only;
- methods STORED (0) and DEFLATE (8); reject all other methods;
- only the extra fields needed by the selected pinned writer/profile;
- ZIP64 only where classic fields cannot represent the actual corpus;
- fixed timestamps and attributes, stable sorted member order, and pinned
  DEFLATE implementation/version/settings;
- central directory bounded to 64 MiB and one million entries; preserve the
  v1 32 MiB default per-asset limit and four-reader workload;
- reject duplicate paths, unsafe names, malformed/truncated records, invalid
  local-header references, out-of-range/overlapping payloads, size mismatches,
  CRC failures, and unsupported ZIP features before returning asset bytes.

First run correctness and determinism checks. Build archives repeatedly and
compare hashes. Exercise empty and UTF-8 names, case-distinct paths, duplicate
names, traversal/absolute/backslash/NUL names, malformed central directories,
ZIP64 boundaries, CRC corruption, inflated-size limits, and concurrent reads.
Require exactly declared decoded size and CRC validation before a complete
asset is returned.

## Measurements

Report separately:

1. **Container-focused arm:** GPack raw entries versus ZIP STORED. This most
   closely isolates catalog and record overhead.
2. **Product-profile arm:** GPack's selected Zstandard/raw behavior versus ZIP
   DEFLATE/STORED behavior. This compares complete codec profiles, not just
   container structures.

Measure archive size, packing time, Goose full-asset lookup throughput and
latency, and peak RSS. Use five paired runs per workload for both pack and read;
alternate format order, keep compiler/build settings and host fixed, and record
compiler, Goose, Zstandard, zlib/DEFLATE, and OS versions.
Readers must use equivalent positional I/O, path resolution, CRC verification,
worker counts, API behavior, and source-byte validation. Report medians and all
raw observations. Do not use Python or a system ZIP tool's results as a
substitute for the Goose runtime comparison.

## Decision rule

Correctness, malformed-input rejection, deterministic output within each
format, and source-byte equivalence are hard gates. Do not claim a general
winner from one corpus. Describe where either profile wins on size, pack cost,
lookup throughput/latency, and memory. Revisit the product format decision only
if the measured difference is material to the accepted workflow and the
maintenance/interoperability tradeoff is stated explicitly. Otherwise record
the result as inconclusive and retain the current user-selected v1 contract.

## Result artifact

Record environment, versions, archive hashes, all raw paired observations,
summary statistics, correctness outcomes, and limitations in `results.md` and
`results.json` alongside this protocol. The experiment used classic ZIP only
and rejects ZIP64, since all selected corpora fit classic fields. The DEFLATE
arm uses system zlib-ng 1.3.1 at level 3 and does not implement per-entry STORE
fallback. These deviations are described in the results.
