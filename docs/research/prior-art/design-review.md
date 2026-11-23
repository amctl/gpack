# GPack design research: binary packers and Goose

> Historical review of the initial proposal, based on sources checked
> 2026-11-22. Current product decisions are in the [v1 specification](../../product/spec.md);
> this review is retained for its prior-art analysis and risk context.

**Scope.** This historical note evaluates the initial product brief in [`proposal.md`](../../product/proposal.md) against established archive/container designs, source implementations, compression format documentation, and the Goose docs and samples bundled in this repository. The accepted product decisions are now in [`spec.md`](../../product/spec.md). Sources were checked 2026-11-22. Where an implementation source is used, it is linked directly so the design can be checked against the code.

## Executive findings

1. A footer index with independently compressed chunks is a sound baseline for an asset archive with streaming writes and random reads. ZIP's central directory and Unreal IoStore's TOC/data split demonstrate the pattern at different interoperability and scale points. Keep the index schema, payload codec framing, integrity model, and path rules fully specified.
2. Deterministic output requires a canonical input manifest and stable encoding decisions, not just sorting worker results. Normalize paths; define duplicate, symlink, timestamp, permission, and Unicode policies; pin codec parameters; and write records in canonical order. Test byte-for-byte reproducibility across worker counts and scheduling.
3. Goose is well suited to owning the format, validation, indexing, and orchestration, but this checkout's standard `os` module is whole-file oriented. The proposed C shim is a practical boundary for streaming/positional I/O and codecs. Keep the shim narrow and define ownership/capacity rules at each FFI call.
4. Goose queues are typed, flat-value message channels. `qput` is nonblocking and returns false on a full queue; `qlimit` limits message count, not a byte budget. A queue of variable-size chunk payloads therefore needs explicit byte-level backpressure. A writer that only consumes the next sequence can deadlock if later results fill the result queue before the missing result can be enqueued.
5. Treat hashes as distinct concepts: a fast non-cryptographic content key for candidate deduplication, and a cryptographic digest or authenticated signature when defending against intentional tampering/collision attacks. Validate the bytes and all offset arithmetic when reading an untrusted archive.

## Prior designs and what to reuse

| Format / implementation | Shape and useful lesson | Limitation for gpack |
|---|---|---|
| ZIP / ZIP64 | Local file records and payloads are followed by a central directory that provides names and extraction metadata. This allows a reader to find the index at the end and then access members without scanning all payload bytes. ZIP is the compatibility baseline when third-party tools matter. [PKWARE APPNOTE](https://support.pkware.com/home/pkzip/developer-tools/appnote), [Library of Congress format description](https://www.loc.gov/preservation/digital/formats/fdd/fdd000354.shtml) | Compatibility rules, timestamps/attributes, local headers, descriptors, and ZIP64 add complexity. A gpack-specific format can make stronger choices, but must document them precisely. |
| Quake PAK / WAD | id Software's [Quake PAK reader](https://github.com/id-Software/Quake/blob/master/WinQuake/common.c) reads a compact directory of name/offset/size records and seeks to payloads. [WAD structures](https://github.com/id-Software/Quake/blob/master/WinQuake/wad.h) similarly map entries to lumps. These are useful minimal examples of an index plus independently addressable data. | Historical formats have limited validation and integrity; use them as structural precedents, not as secure parser models. |
| Unreal Pak / IoStore | Epic's [Zen Loader docs](https://dev.epicgames.com/documentation/unreal-engine/zen-loader-in-unreal-engine) describe a `.utoc` table of contents containing chunk offsets/sizes, codec and encryption information, with content in `.ucas`. The [FPakEntry API](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/PakFile/FPakEntry?application_version=5.8) exposes compression blocks and file offsets. This validates the use of independently addressable chunks and metadata tables for game assets. | This is a mature engine-specific format and I/O stack. Its complexity is not a target for gpack v1; extract the chunk/TOC lessons only. |
| Zstandard Seekable Format | The [seekable format](https://github.com/facebook/zstd/blob/dev/contrib/seekable_format/zstd_seekable_compression_format.md) combines independent Zstd frames and a footer table with compressed/decompressed sizes and checksums. It is an option if gpack wants seekable compressed streams. | It does not define gpack paths, deduplication, metadata, extraction safety, or a complete archive catalog. |
| CARv1 / CARv2 | [CARv1](https://ipld.io/specs/transport/car/carv1/) is a length-prefixed stream; [CARv2](https://ipld.io/specs/transport/car/carv2/) wraps that stream with offsets and an optional index for random access. This shows a useful evolution path from simple streaming to indexed access. | CAR is content-addressed block transport, not a filesystem archive; its specs leave deterministic ordering/dedup policy to applications. |
| OCI content descriptors | OCI [descriptors](https://github.com/opencontainers/image-spec/blob/main/descriptor.md) bind a content digest to a byte size, and OCI [layers](https://github.com/opencontainers/image-spec/blob/main/layer.md) establish conventions around packaged filesystem changes. This is a useful model for integrity metadata and immutable content identity. | OCI's layered image semantics are broader than a simple pack/unpack tool. |

### Design consequences

- Keep the gpack index at the end if sequential output is the priority. Include an explicit index offset and length in a fixed header, then write a canonical index. A reader should validate that the index lies wholly within the archive, that record ranges do not overflow or overlap forbidden regions, and that referenced chunks fit within the payload area.
- Decide whether payload records are per-file, per-chunk, or both. Per-file compression is simple and maps naturally to ZIP. Fixed or variable-sized independent chunks support partial reads and bounded memory. A large file can be described as an ordered list of chunk references.
- Keep the initial format narrow: one specified byte order, fixed-width integers for archive offsets/sizes, explicit codec identifiers, reserved fields that must be zero, and a major/minor compatibility rule. Do not encode native Goose structs as the public format.
- Treat deduplication as optional metadata layered on chunk identity. Hash matches should be confirmed by size and bytes (or a cryptographic digest under an explicit threat model); collision-prone fast hashes alone are not proof that two chunks are equal.
- Make each compressed chunk independently decodable. LZ4's [frame format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md) explicitly notes that linked blocks depend on prior blocks, which prevents random access and parallel decoding; independent blocks trade some ratio for those capabilities. Zstandard exposes frame content-size and checksum controls in its [API manual](https://facebook.github.io/zstd/doc/api_manual_latest.html).
- Compression fallback should be based on actual encoded size and a documented threshold. Unreal's project settings expose minimum bytes and percentage saved for retaining compressed blocks, demonstrating that this is a practical policy knob ([Epic settings reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/project-section-of-the-unreal-engine-project-settings)). Avoid extension-based skip rules as the correctness mechanism; already-compressed inputs will naturally fail the gain threshold.

## Determinism, safety, and operational behavior

### Deterministic builds

Assign every asset and chunk a stable sequence after canonical path sorting, then serialize in that order regardless of worker completion order. Define all metadata that otherwise inherits host state: timestamps, modes, path separators, path encoding/normalization, duplicate path behavior, and symlink policy. Pin codec ID, level, frame options, dictionary identity, and codec version policy. A stable archive version should say whether output is guaranteed identical across platforms and library versions, or only for a pinned toolchain/configuration.

The existing Goose [`23_mandelbrot_threads.goose`](../../../goose-bin/samples/23_mandelbrot_threads.goose) intentionally collects worker results out of order and separately reconstructs the desired order. That is a useful concurrency example, but gpack needs a bounded reorder strategy. Assign work in bounded windows and allow the coordinator to consume any completion while preserving a bounded number/byte count of in-flight chunks. Do not block waiting for sequence *k* while the queue may be full of later results and the worker for *k* is trying to enqueue.

### Path and archive validation

Normalize archive paths to a specified relative slash-separated form. Reject absolute paths, `..` components, invalid encodings, and duplicate normalized paths unless a deliberate overwrite rule exists. During extraction, resolve every destination under the chosen output root and do not follow archive-controlled symlinks outside it. libarchive's own extraction flags (`SECURE_NOABSOLUTEPATHS`, `SECURE_NODOTDOT`, `SECURE_SYMLINKS`) make these common threat classes explicit in a mature implementation ([header](https://github.com/libarchive/libarchive/blob/master/libarchive/archive.h)).

Check every addition/multiplication used for `offset + length`, record-count sizing, and decompressed output limits before allocation or I/O. Cap archive counts, path lengths, chunk sizes, decompressed sizes, and total output; reject unknown major versions and unsupported codecs clearly. Hash/checksum validation detects corruption but does not by itself authenticate an archive. xxHash's own [documentation](https://xxhash.com/) labels XXH3-128 non-cryptographic; reserve SHA-256 (or a signature) for the integrity/authenticity contract that needs it.

### Atomic output

Build into a temporary sibling file, flush and close it, optionally reopen and validate its header/index, then replace the destination. On POSIX, `rename` atomically replaces a destination name when successful ([Linux man page](https://man7.org/linux/man-pages/man2/rename.2.html)); cross-platform replacement and durability semantics still need a platform-specific wrapper. Do not patch an existing archive in place for v1. A failed worker or validation must leave the previous completed archive untouched.

## Goose fit and constraints in this checkout

The local Goose version reports `goose v2026.4`. The docs and samples below are in this repository, so they are the best evidence for the language available to this project:

| Goose feature | Evidence in this checkout | Implication |
|---|---|---|
| Scope-reclaimed growable arrays and inline variable-size values | [`goose-bin/README.md`](../../../goose-bin/README.md), [`goose-bin/docs/goose_spec.md`](../../../goose-bin/docs/goose_spec.md) | Good for worker-local read/compress buffers and compact metadata. Keep each chunk's scratch state inside one operation/scope instead of accumulating all raw content. |
| Typed thread queues; flat values copied across worker boundaries; queue insertion can fail | [`goose-bin/docs/reference.md`](../../../goose-bin/docs/reference.md#22-threads), [`goose-bin/samples/23_mandelbrot_threads.goose`](../../../goose-bin/samples/23_mandelbrot_threads.goose) | Jobs/results can carry inline variable-size payloads, but that means queue copies consume memory. Check every `qput` result and make backpressure explicit. Queue count limits do not cap payload bytes. |
| Goose workers have separate program memory | [`goose-bin/docs/reference.md`](../../../goose-bin/docs/reference.md#22-threads), [`goose-bin/samples/32_pool_worker_snapshots.goose`](../../../goose-bin/samples/32_pool_worker_snapshots.goose) | Pass immutable source information and values through queues; never assume a shared Goose manifest or output buffer. Avoid copying a large read-only manifest into every worker spawn. |
| Whole-file convenience I/O, atomic helper, directory listing | [`goose-bin/docs/stdlib.md`](../../../goose-bin/docs/stdlib.md#os), [`goose-bin/stdlib/os.goose`](../../../goose-bin/stdlib/os.goose) | Current `read_file` materializes an entire file; it is not sufficient alone for bounded-memory streaming. The C boundary is justified for open/read-at/write/flush/replace calls. |
| C interop for slices/builders and program-owned C sidecars | [`goose-bin/samples/24_call_c.goose`](../../../goose-bin/samples/24_call_c.goose), [`goose-bin/docs/packages.md`](../../../goose-bin/docs/packages.md#3-a-program-with-c-of-its-own) | Use a small C ABI for positional I/O, compression, and high-performance hashes; keep archive semantics and validation in Goose. A slice reaches C as pointer+length, and a Goose byte builder can be appended to. |
| Serialization verification | [`goose-bin/samples/25_serialize.goose`](../../../goose-bin/samples/25_serialize.goose) | Goose `from_bytes` verifies Goose's own relative-link representation, but this is not a replacement for the independently versioned gpack format. The sample explicitly distinguishes structural safety verification from checksum/integrity. |
| Directory traversal example | [`goose-bin/samples/26_file_tree.goose`](../../../goose-bin/samples/26_file_tree.goose) | Useful data-structure example only; real scanning must also define symlink behavior, races with changing files, errors, and path canonicalization. |

### Scheduler correction to the current brief

The proposed design's sequence-order writer and bounded queues need a scheduler contract before implementation:

1. Set queue limits before spawning workers and check `qput(job)` / `qput(result)` booleans.
2. Bound *in-flight bytes*, not only message count. A conservative initial budget can be `worker_count × (raw_chunk + worst_case_compressed_chunk + metadata)` plus a bounded coordinator reorder budget.
3. Avoid the head-of-line deadlock: consume available results and place them in a bounded sequence map, or constrain issuance so the missing earliest chunk always has capacity to return. The coordinator must continue draining results while waiting for slow work.
4. On worker errors, propagate a result status and stop issuing work; drain or cancel workers, wait for all IDs, and remove the temporary archive. `thread_spawn_contained` can keep one worker abort from taking down main, but it does not close C file handles automatically (the reference docs state native resources remain open).
5. Shut workers down only after all jobs have been issued and results collected; use one sentinel per worker or another explicit termination protocol. Ensure shutdown messages cannot be starved behind unbounded queued work.

The current sample `23_mandelbrot_threads.goose` queues all work before starting workers and uses an unbounded queue in that small fixed-size demo. That pattern is not safe to scale directly to a packer handling arbitrarily many files or multi-megabyte payloads. Also, `goose run` cannot execute threaded programs with the bundled TinyCC path; use `goose build` for real concurrency ([command line docs](../../../goose-bin/docs/command_line.md#2-running-a-program)).

## Suggested v1 decisions

These are design recommendations to resolve before code is written:

1. **Archive:** fixed header, sequential payload area, footer index, fixed-width little-endian fields, major/minor version, and explicit codec/flag values. Specify whether a file maps to one or multiple independent chunks.
2. **Index:** canonical path-sorted asset records and chunk records. Store path bytes in a string table or length-prefixed record. Use 64-bit archive offsets/sizes even if current chunks are much smaller.
3. **Chunking:** benchmark at 256 KiB, 1 MiB, and 4 MiB against real game asset corpora; do not make a 1 MiB default a fact until measured. The LZ4 frame's supported independent block sizes include those scales, and Epic exposes block-size tuning as a packaging option.
4. **Codecs:** begin with raw and one independently framed codec (Zstandard if compression ratio/choice is the priority, LZ4 if fast decode is the priority). Add codecs only with stable codec IDs and conformance vectors. Avoid simultaneously linking more native dependencies before the core format is proven.
5. **Checks:** record raw size and a raw-content digest per chunk; optionally enable codec-frame checksums too. Use SHA-256 for an explicitly security-sensitive mode; do not describe xxHash as security protection.
6. **Deduplication:** defer until a basic archive is stable, or limit v1 to whole-chunk exact-byte dedup with a well-defined owner/reference record. A hash collision must not silently alias distinct content.
7. **Extraction:** reject traversal/absolute/duplicate paths; impose output limits; write extracted files via temp+rename where practical; specify whether metadata and symlinks are preserved.
8. **Reproducibility:** include golden archive fixtures and compare exact bytes under several worker counts. Specify the guarantee boundary around codec library versions and platform settings.
9. **Benchmarking:** measure scan, read, hash, compress, write, and extract separately; include already-compressed assets and incompressible data; report throughput and peak RSS as well as compression ratio. Avoid comparing only synthetic compressible buffers.

## Source index

Primary sources used above:

- [Goose reference: threads and queues](https://github.com/aardappel/goose/blob/master/docs/reference.md#22-threads)
- [Goose samples index](https://github.com/aardappel/goose/tree/master/samples)
- [Goose C interop/package docs](https://github.com/aardappel/goose/blob/master/docs/packages.md)
- [PKWARE ZIP APPNOTE](https://support.pkware.com/home/pkzip/developer-tools/appnote)
- [id Software Quake PAK reader](https://github.com/id-Software/Quake/blob/master/WinQuake/common.c)
- [id Software WAD structures](https://github.com/id-Software/Quake/blob/master/WinQuake/wad.h)
- [Epic Zen Loader](https://dev.epicgames.com/documentation/unreal-engine/zen-loader-in-unreal-engine)
- [Epic FPakEntry API](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/PakFile/FPakEntry?application_version=5.8)
- [Zstandard seekable format](https://github.com/facebook/zstd/blob/dev/contrib/seekable_format/zstd_seekable_compression_format.md)
- [Zstandard API manual](https://facebook.github.io/zstd/doc/api_manual_latest.html)
- [LZ4 Frame format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md)
- [xxHash](https://xxhash.com/)
- [CARv1](https://ipld.io/specs/transport/car/carv1/), [CARv2](https://ipld.io/specs/transport/car/carv2/)
- [OCI descriptor](https://github.com/opencontainers/image-spec/blob/main/descriptor.md), [OCI layer](https://github.com/opencontainers/image-spec/blob/main/layer.md)
- [libarchive extraction security flags](https://github.com/libarchive/libarchive/blob/master/libarchive/archive.h)
- [POSIX/Linux rename behavior](https://man7.org/linux/man-pages/man2/rename.2.html)
- [Unreal compression threshold settings](https://dev.epicgames.com/documentation/en-us/unreal-engine/project-section-of-the-unreal-engine-project-settings)
