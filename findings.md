# Findings

## Current understanding

This checkout does not yet implement gpack. `PRODUCT.md` proposes a new asset
archive and a native Goose/C split. The bundled Goose tree provides strong
building blocks for control flow, typed data, binary parsing, and safe
serialization, but the current standard `os` surface is whole-file oriented.
For large assets, a native streaming I/O boundary is therefore not an optional
optimization; it is the apparent prerequisite unless the standard library is
extended.

Prior formats show that the major format choice is the access model. ZIP keeps
entry-local headers and an end central directory to support streaming and
random access, at the cost of duplicated metadata. libarchive deliberately
optimizes for streaming and independent entries, while acknowledging that
random access is a separate requirement. Zstandard's seekable extension uses
independent frames plus a seek table; frame size trades random access latency
against ratio. Quake II's PAK is a compact, simple precedent for a payload area
followed by a directory, but its fixed-width names and integer limits are not a
good modern compatibility target.

Goose's worker model fits coarse jobs and flat results, but not a naïve design
that copies large payload arrays through queues. Queue limits count messages,
not aggregate bytes. The local Mandelbrot sample demonstrates the intended
worker pattern for small results: workers complete out of order and a sequence
or key restores output order. The archive writer can reuse the ordering idea,
but needs byte-based backpressure and an explicit memory budget.

The proposal's claimed 1 MiB default and chosen hashes/codecs are hypotheses,
not conclusions. A first comparison should measure whole-file frames and
fixed-size chunks across small files, large files, already-compressed assets,
and repeated content. File-boundary versus cross-file chunking, deduplication,
metadata preservation, symlink policy, and reproducibility rules need explicit
scope before a format is frozen.

## Patterns and insights

- Keep archive parsing/validation in Goose where checked arithmetic and
  `binary` helpers are useful; place streaming handles and mature codecs behind
  a narrow C ABI.
- Define determinism over normalized paths, entry ordering, metadata policy,
  codec version/parameters, and source snapshot behavior. Sorting only the
  worker results is insufficient.
- Make extraction validation a first-class format requirement: validate all
  ranges and sizes before allocation or writes, normalize/reject unsafe paths,
  and prevent path traversal and symlink escapes.
- Distinguish content identity from integrity/authenticity. A fast non-crypto
  hash can index candidates; it cannot prove maliciously chosen data is intact.
  Verify byte equality after hash matches and use a cryptographic digest or
  authenticated mechanism when the threat model requires it.
- Use atomic finalization (write a sibling temporary archive, flush, rename)
  rather than patching the only destination in place. Goose already exposes an
  atomic whole-file operation, but a large archive needs a streaming equivalent
  in the native layer.

## Lessons and constraints

- Do not infer whole-file I/O scales from `read_file`; it appends the complete
  file to a Goose array.
- Do not call bounded queues a byte-bounded pipeline: one message can still
  hold an arbitrarily large flat array.
- Do not treat `from_bytes` as a general archive parser. It verifies Goose's
  own image format; `stdlib/binary.goose` is the intended checked primitive for
  external formats.
- Do not promise reproducible output without defining timestamps, permissions,
  path separators/Unicode normalization, input mutation, and compression
  library/version policy.
- Do not store public on-disk records by dumping Goose structs. Use explicitly
  encoded fixed-width fields and versioned framing; host struct layout is not a
  durable format contract.

## Open questions

1. Is the primary goal a game/runtime asset archive with random reads, a
   general-purpose archiver, or an embedded-resource compiler tool?
2. Which asset corpus and target platforms define success?
3. Should compatibility with existing formats be an explicit goal, or is a
   custom format justified by the runtime workload?
4. Are cross-file deduplication and cryptographic verification requirements or
   later extensions?
5. Can the C ABI use a maintained system codec dependency, or must it be
   self-contained across the platforms Goose targets?

## Proposed next research cycle

Lock H1-H3 protocols in `experiments/` before implementing a benchmark. Compare
the Goose queue pipeline with a baseline that sends only small job/result
metadata while payloads are staged through native file handles or temporary
files. Report throughput and peak memory together; a throughput-only win that
uses unbounded memory is not a valid success.
