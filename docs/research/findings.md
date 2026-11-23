# Findings

## Current understanding

The accepted v1 contract and architecture are in the [product specification](../product/spec.md)
and [architecture map](../product/architecture.md). The product implementation
is in place. The H3 runtime prototype passed correctness but missed its
throughput target; the product v1 reader later met the median throughput gate
in five paired Linux runs after CRC and small-frame decode optimizations.
Cross-platform validation remains open.

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

The earlier product proposal's 1 MiB chunk default, multiple codecs, hashes,
and deduplication were not accepted as v1 requirements. H2 supports
per-asset frames for the whole-asset API and showed no material framing
advantage on the small real corpus; v1 uses raw fallback when compression does
not reduce size. H1 supports metadata staging only in selected generated
workloads, not as a general default.

## Patterns and insights

- Keep archive parsing/validation in Goose where checked arithmetic and
  `binary` helpers are useful; place streaming handles and mature codecs behind
  a narrow C ABI.
- Define determinism over normalized paths, entry ordering, metadata policy,
  codec version/parameters, and source snapshot behavior. Sorting only the
  worker results is insufficient.
- If extraction is added later, make extraction validation a first-class
  requirement: validate all
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
  path separators and path-byte/case behavior, input mutation, and compression
  library/version policy.
- Do not store public on-disk records by dumping Goose structs. Use explicitly
  encoded fixed-width fields and versioned framing; host struct layout is not a
  durable format contract.

## Open acceptance risks

1. The user selected a new versioned format, but the current measurements do
   not demonstrate an advantage over restricted ZIP. Keep the format narrow
   and revisit the decision if the implementation fails to deliver the selected
   runtime API or safety contract.
2. Issue 22's product v1 benchmark met the agreed 10% median throughput gate
   on Linux. The production CMake build and other platform measurements remain
   for issue 23.
3. Zstandard 1.5.7 is pinned, but cross-platform output identity and the
   selected 32 MiB/four-reader memory defaults are unmeasured across targets.
4. Path behavior preserves valid UTF-8 bytes and case. Cross-platform tests
   must cover non-ASCII names and case distinctions before release.
5. CRC32 and Zstandard frame checksums detect accidental corruption only; the
   v1 contract makes no authenticity claim.

The pinned Godot 4.7 corpus is now inventoried: `2d/kinematic_character`,
`3d/lights_and_shadows`, and `audio/mic_record`, with release checksums verified
and the CC0 checker notice retained. See the
[`corpus manifest`](experiments/godot-4.7-corpus/manifest.json) for complete
candidate counts, notice review, and per-file hashes.

## Research summary and next work

H1, H2, and both H3 experiments are complete. The [H2 report](experiments/h2-frame-granularity/results.md)
found that per-asset frames did not materially distinguish layouts on the real
corpus, while chunking helped large high-entropy and mixed controls and greatly
hurt repeated-content compression. The [H3 pack report](experiments/h3-native-streaming-boundary/results.md)
found that native streaming substantially reduced pack-side memory on large
controls and stayed within its C throughput gate. The [H3 runtime report](experiments/h3-runtime-lookup/results.md)
passed source-byte and malformed-input gates but missed its 10% throughput gap
on both workloads. The [H1 report](experiments/h1-queue-payload-cost/results.md)
supports metadata staging selectively for large high-entropy work at higher
worker counts.

The pinned corpus remains one notice-cleared Godot 4.7 demo from each of 2D,
3D, and audio, plus deterministic generated controls. The runtime performance
gate is complete for the measured Linux build. Remaining release validation is
tracked by issue 23; implementation tasks are in the [Wayfinder graph](../../.scratch/gpack-foundation/map.md).

## H3 indexed runtime follow-up

The historical [H3 runtime comparison](experiments/h3-runtime-lookup/results.md) found that
Goose-owned parsing/path lookup over native positional reads and Zstandard
passed source-byte and malformed-input gates. Goose throughput was 27.4% below
the C reference on the Godot corpus and 12.1% below it on mixed, missing the
predeclared 10% maximum gap. The follow-up [product v1 benchmark](experiments/v1-runtime-throughput/results.md)
then passed the median throughput gate on one Linux host and remeasured the
four-reader/32 MiB defaults. The narrow ABI is performance-accepted for that
measured build; other supported platforms remain part of issue 23.
