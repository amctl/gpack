# Prior art survey: binary asset packing and Goose

Survey date: 2026-11-22. This is a source-grounded engineering survey, not an
exhaustive literature review. Primary sources are preferred: format/library
specifications, project documentation, and source code. Local observations are
identified as such.

## Summary

The main design axis is not simply “compression on or off.” It is the
interaction among streaming construction, random access, independent decode
units, metadata placement, and bounded memory. ZIP and PAK demonstrate
directory/indexed archives; libarchive demonstrates stream-first abstraction;
Zstandard seekable frames demonstrate indexed independent compression units.
Goose contributes memory-safe data construction, checked external binary
parsing, compiler-verified image deserialization, and a no-shared-mutable-memory
thread model. Its current standard file API does not expose streaming handles,
so scalable archive I/O likely needs a small native layer.

## Binary archive and packer prior art

### ZIP

The ZIP design uses local file headers alongside content and a central
directory at the end. This accommodates streaming creation and efficient
directory-based lookup, with metadata duplicated between local and central
records. libarchive's implementation documentation explains that this
tradeoff is also why a purely stream-oriented reader and a seekable central
directory reader differ. The authoritative format specification is PKWARE's
[ZIP Application Note](https://www.pkware.com/documents/casestudies/APPNOTE.TXT).
The implementation discussion is in the [libarchive ZIP format notes](https://github.com/libarchive/libarchive/wiki/FormatZip).

**Relevance:** a useful compatibility baseline and proof that streaming plus
random access can coexist, but the feature-rich ZIP format brings legacy
compatibility surface and is not automatically the right custom asset format.

### libarchive

The project's own design notes describe a heavily stream-oriented API, with
independent entries, custom I/O callbacks, and no direct in-place modification
or random access guarantee. Some formats can be reopened and scanned where
true random access is unnecessary. See [libarchive design notes](https://github.com/libarchive/libarchive#notes-about-the-library-design)
and its [format capabilities](https://github.com/libarchive/libarchive).

**Relevance:** keep the core writer streaming and entries independent if
streaming is a primary goal. Do not assume a generic archive abstraction gives
random access for free; random access needs a seekable index or a format
specific lookup layer.

### Zstandard and seekable frames

The Zstandard seekable extension divides compressed data into independent
frames and appends a table so a reader can find frames without decompressing
the entire stream. Its own header notes the tradeoff: smaller frames improve
small-range reads but can reduce compression ratio. The format API supports
building a frame log for independently compressed frames that are assembled
later, making it a particularly close prior for parallel archive payload
construction. See [Zstandard seekable format](https://github.com/facebook/zstd/blob/dev/contrib/seekable_format/zstd_seekable.h),
[compression API](https://github.com/facebook/zstd/blob/dev/lib/zstd.h), and
[format specification](https://github.com/facebook/zstd/blob/dev/doc/zstd_compression_format.md).

**Relevance:** frame granularity should be selected from measured access
patterns. The independent-frame/table structure maps naturally to deterministic
parallel work, but actual framing and codec version must be part of the format
contract.

### Quake II PAK

The Quake II Tools source contains a concrete PAK writer with a compact header,
fixed-size filename entries, payload offsets/lengths, and directory emission
after data. See [`qdata.c`](https://github.com/id-Software/Quake-2-Tools/blob/master/qdata/qdata.c).

**Relevance:** a small, understandable example of the payload-then-directory
pattern and a good educational baseline. Its fixed-width path and integer
choices expose the cost of freezing underspecified limits into a format.

### UnityFS (implementation reference)

The AssetStudio reader models a bundle header, block records, directory nodes,
per-block compression flags, and metadata that may occur at the end of the
bundle. See [`BundleFile.cs`](https://github.com/Perfare/AssetStudio/blob/master/AssetStudio/BundleFile.cs).
This is a reverse-engineered consumer implementation rather than an authoritative
Unity specification, and the repository is archived; use it as implementation
prior art only.

**Relevance:** block metadata and data-block abstraction are useful examples
for asset engines that need selective loading. It also illustrates why a
format's real-world behavior should be documented from the writer and reader,
not inferred from a proposed record table alone.

### Go `embed`

Go's official `embed` package generates a read-only filesystem image from
compile-time path patterns. It sorts names and exposes the virtual filesystem
through the standard `io/fs` interface. See [Go embed package](https://github.com/golang/go/blob/master/src/embed/embed.go).

**Relevance:** for assets shipped with an executable, a generated embedded
filesystem may be the simpler baseline than a runtime archive. It avoids a
separate container and runtime parser, while not solving post-build updates,
large external content, or independent deployment.

## Goose language and program prior art

### Data representation and serialization

The local Goose implementation note describes verified deserialization for
self-relative data images: framing and links are checked before bytes become a
typed Goose value. The local `samples/25_serialize.goose` builds and saves an
index as its own byte image, then demonstrates that verification is about
structural safety rather than integrity. External archive metadata should use
`stdlib/binary.goose`, which reads explicit endian fields and checks ranges;
`from_bytes` is not an archive parser.

Upstream sources: [serialization design](https://aardappel.github.io/goose/docs/design/serialization.html),
[binary/stdlib docs](https://aardappel.github.io/goose/docs/stdlib.html).

### Threads and queues

The Goose specification states that worker programs have separate storage,
arguments and queue values must be flat, and typed queue puts copy values. A
bounded queue limits message count and `qput` fails immediately when full; it
does not establish an aggregate payload-byte limit. The local
`samples/23_mandelbrot_threads.goose` uses this model successfully for small
row messages, collects results in arbitrary completion order, then restores
row order. `samples/32_pool_worker_snapshots.goose` shows workers receiving
copied snapshots of pools.

Upstream sources: [Goose concurrency specification](https://aardappel.github.io/goose/docs/goose_spec.html#112-concurrency),
[implementation notes](https://aardappel.github.io/goose/docs/implementation.html).

**Relevance:** use queues for job descriptors and small results. For large
asset chunks, account for copies and maintain byte-based in-flight limits; a
metadata-only message plus native staging may be preferable.

### Filesystem and FFI

The local `stdlib/os.goose` API includes whole-file reads/writes, atomic
whole-file replacement, directory creation/listing, and path-based operations.
It does not include persistent handles, `pread`-style positional reads, or
streaming output. Goose's C FFI and package build support provide an established
boundary for adding those operations. The bundled graphics and physics packages
are examples of Goose-facing APIs backed by native C implementations.

Upstream sources: [stdlib reference](https://aardappel.github.io/goose/docs/stdlib.html),
[package docs](https://aardappel.github.io/goose/docs/packages.html).

**Relevance:** a narrow C layer for file handles, positional I/O, codec
wrappers, and atomic finalize aligns with the existing architecture. Keep the
archive schema, validation, policy, CLI, and indexing in Goose to retain the
language-specific value.

### Useful local sample corpus

| Sample | Demonstrated pattern | gpack relevance |
|---|---|---|
| `12_huffman.goose` | Prefix-code compression algorithm | Algorithm exercise; not a production codec recommendation |
| `23_mandelbrot_threads.goose` | Typed worker queues; order-independent completion | Parallel scheduling and deterministic reassembly pattern |
| `25_serialize.goose` | Verified data image and external format safety distinction | Format parsing and corruption model |
| `31_mini_doom.goose` | WAD directory parsing and game asset loading | Closest bundled real archive consumer |
| `32_pool_worker_snapshots.goose` | Explicit worker state copies | Highlights share-nothing cost |
| `stdlib/binary.goose` | Bounds-checked endian readers | Useful for archive parser implementation |
| `pkg/gfx`, `pkg/physics` | Goose API over native static libraries | Precedent for codecs/native I/O boundary |

## Gaps and design implications

1. No existing gpack implementation or benchmark baseline was found in this
   checkout. Any throughput claims in `PRODUCT.md` remain untested.
2. The proposed queue results embed `payload: u8[]`; Goose flat queue semantics
   copy that payload. Bound the total bytes in flight explicitly or avoid
   transferring large payloads as Goose values.
3. The proposed default chunk size and codec/hash defaults have no corpus-based
   evidence yet. Test small-file overhead, large-file access, already-compressed
   data, and deduplication independently.
4. Define the threat model and extraction contract before finalizing the
   format: bounds validation, archive bombs/resource limits, duplicate paths,
   absolute paths, `..`, symlinks, case folding, Unicode normalization, and
   atomic file replacement all affect safe extraction.
5. Define reproducibility precisely: normalized relative names and bytewise
   sort, metadata inclusion/removal, timestamp policy, codec settings/version,
   source mutation during packaging, and platform path behavior.
6. Store all public fields with explicit byte order and fixed widths; do not
   dump Goose structs. Add a versioned header, bounded index, and redundant
   integrity fields only when their purpose and coverage are defined.

## Candidate hypotheses

### H1 — Queue payload copy cost

**Prediction:** as chunk size and worker count rise, a result queue carrying
entire compressed chunks will consume materially more memory and can reduce
throughput versus a native staging path that queues only small descriptors.

**Measure:** end-to-end throughput, peak resident memory, and time in read,
hash, compression, queue transfer, ordered write; sweep worker count and chunk
size on both compressible and incompressible corpora.

### H2 — Granularity tradeoff

**Prediction:** whole-file frames are better for many small independent assets,
while fixed-size chunks improve partial reads for large assets, at a cost in
index overhead and possibly compression ratio.

**Measure:** compressed archive size, index size, lookup/extract latency,
verification throughput, and working set across mixed corpora.

### H3 — Goose policy layer plus C streaming backend

**Prediction:** implementing streaming file I/O and codec calls behind a narrow
C ABI permits bounded memory while keeping archive behavior in Goose, with
performance close to a C baseline and better auditability than an all-C packer.

**Measure:** throughput, peak memory, LOC/complexity by subsystem, correctness
and malformed-input handling versus a minimal C reference.

## References

- PKWARE, [ZIP Application Note](https://www.pkware.com/documents/casestudies/APPNOTE.TXT).
- libarchive, [design notes](https://github.com/libarchive/libarchive#notes-about-the-library-design), [ZIP design](https://github.com/libarchive/libarchive/wiki/FormatZip), [source](https://github.com/libarchive/libarchive).
- Meta, [Zstandard format](https://github.com/facebook/zstd/blob/dev/doc/zstd_compression_format.md), [seekable format](https://github.com/facebook/zstd/blob/dev/contrib/seekable_format/zstd_seekable.h), [C API](https://github.com/facebook/zstd/blob/dev/lib/zstd.h).
- id Software, [Quake II Tools PAK writer](https://github.com/id-Software/Quake-2-Tools/blob/master/qdata/qdata.c).
- Perfare, [AssetStudio UnityFS reader](https://github.com/Perfare/AssetStudio/blob/master/AssetStudio/BundleFile.cs) (archived implementation; not normative).
- Go project, [embed package](https://github.com/golang/go/blob/master/src/embed/embed.go).
- Goose, [specification](https://aardappel.github.io/goose/docs/goose_spec.html), [implementation notes](https://aardappel.github.io/goose/docs/implementation.html), [serialization design](https://aardappel.github.io/goose/docs/design/serialization.html), [stdlib](https://aardappel.github.io/goose/docs/stdlib.html), [packages](https://aardappel.github.io/goose/docs/packages.html).
- xxHash, [algorithm specification](https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md) (explicitly non-cryptographic).
