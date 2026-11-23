# gpack: a proposed asset packer for Goose

> **Status:** Historical initial proposal; superseded by the accepted
> [gpack v1 specification](spec.md), [format contract](../format/v1.md), and
> [architecture map](architecture.md). The recommendations below were not all
> selected: notably chunking defaults, multiple codecs, deduplication,
> extraction, and the original CLI surface. Use the canonical documents for
> current product and implementation decisions. This proposal is retained as
> design history and as context for the prior-art review.

This proposal recommends a native, deterministic, multithreaded asset
packaging system rather than a simple file concatenator. It targets the
[Goose programming language](https://aardappel.github.io/goose/) by Wouter van
Oortmerssen. Goose's memory model differs from conventional C, C++, and Rust:
dynamic data lives on compiler-managed data stacks, with scope-based
reclamation and no general-purpose heap allocator. That should influence the
architecture.

## 1. Define the target

I'd design the project as a standalone tool named `gpack`.

**GPACK**

Native binary tooling

### Asset packaging engine

One archive. Fast ingestion. Deterministic output. Efficient extraction.

**High throughput**

Parallel scanning, compression and writing

**Integrity**

Checksums, validation and corruption detection

**Low memory**

Bounded buffers and streaming I/O

**Extensible**

Versioned format, codecs and metadata

### Core feature set

| Feature         | Requirement                                       |
| --------------- | ------------------------------------------------- |
| File ingestion  | Recursive directory scanning                      |
| Packaging       | Single binary archive                             |
| Compression     | None, Zstandard, LZ4                              |
| Integrity       | xxHash64 and SHA-256                              |
| Deduplication   | Content-based chunk deduplication                 |
| Parallelism     | Concurrent processing workers                     |
| Extraction      | Selective and full extraction                     |
| Random access   | Direct lookup without unpacking everything        |
| Metadata        | Paths, sizes, offsets, checksums and flags        |
| Reproducibility | Identical inputs produce identical archives       |
| Compatibility   | Format versioning and validation                  |
| CLI             | Pack, unpack, list, inspect, verify and benchmark |

## 2. Recommended architecture

Separate the application into six subsystems.

**CLI / Configuration**

Arguments, filters, compression settings, output path

**Asset Scanner**

Directory traversal, path normalization, metadata, sorting

**Chunk Scheduler**

Chunk creation, bounded job queues, worker assignment

**Worker 1**

Read, hash, compress

**Worker 2**

Read, hash, compress

**Worker N**

Read, hash, compress

**Archive Writer**

Ordered chunk writing, index generation, atomic finalization

**GPACK Binary Archive**

Header · Payload · Index · Integrity metadata

The important design decision is that workers should not write directly into the same output file.

Instead:

1. The scanner produces a deterministic list of assets.
2. The scheduler divides assets into chunks.
3. Workers independently process chunks.
4. Workers return chunk results through Goose's typed queues.
5. The main thread writes chunks in deterministic sequence order.
6. The writer creates the index and finalizes the archive.

This avoids shared mutable state and makes payload order independent of worker
completion order. Reproducibility also depends on normalized paths, stable
metadata policy, source snapshot behavior, and pinned codec versions and
parameters; those details still need to be specified.

## 3. Design the binary archive format

Do not start by serializing Goose structs directly into your public archive format.

Goose has built-in serialization facilities, including `to_bytes`, `bytes_of`
and `from_bytes`, with safety verification for its own serialization
representation. This proposal uses a separately specified format for GPACK to
maintain control over compatibility, layout, and future implementations in
other languages.

### Proposed GPACK v1 layout

**GPACK archive**

Version 1

**64-byte header**

Magic · Version · Flags · Counts · Index offset

**Payload region**

Compressed or uncompressed data chunks

**Asset index**

Asset records · Chunk records · String table

**Optional footer**

Archive checksum · Format extensions

I'd define the header like this:

| Offset | Field                     | Size |
| ------ | ------------------------- | ---- |
| 0      | Magic (8-byte signature; value to be decided) | 8    |
| 8      | Major version             | 2    |
| 10     | Minor version             | 2    |
| 12     | Flags                     | 4    |
| 16     | Chunk size                | 4    |
| 20     | Reserved                  | 4    |
| 24     | Asset count               | 8    |
| 32     | Chunk count               | 8    |
| 40     | Index offset              | 8    |
| 48     | Index size                | 8    |
| 56     | Header CRC32              | 4    |
| 60     | Reserved                  | 4    |

All multibyte fields should use explicitly specified little-endian encoding.

The asset index should contain:

**Asset record**

```
asset_id
path_offset
path_length
original_size
first_chunk
chunk_count
asset_hash
flags
```

**Chunk record**

```
asset_id
chunk_index
payload_offset
compressed_size
original_size
compression_codec
checksum
```

**String table**

```
assets/models/player.mesh
assets/textures/player.png
assets/audio/music.ogg
assets/shaders/lighting.spv
```

The index is stored at the end of the archive. This allows the writer to stream payloads sequentially without needing to know the final index offset in advance.

Once all chunks and the index have been written, patch the header with the final offsets and checksums.

### Why this format?

It gives you:

- Direct asset lookup.
- Random chunk access.
- Partial extraction.
- Independent chunk decompression.
- Efficient verification.
- Future-compatible format extensions.
- No need to unpack the entire archive to retrieve one asset.

Keep a major/minor version distinction and reject unsupported major versions.

## 4. Use chunk-based processing

Never treat an entire directory as one giant byte array.

I'd start with configurable chunk sizes:

| Chunk size | Characteristics                             |
| ---------- | ------------------------------------------- |
| 64 KiB     | Fine-grained random access, higher overhead |
| 256 KiB    | Good general-purpose starting point         |
| 1 MiB      | Lower metadata overhead, good throughput    |
| 4 MiB      | Useful for large sequential assets          |

My suggested initial default is **1 MiB**, with 256 KiB and 4 MiB available for benchmarking.

For each chunk:

```
Read source bytes
       |
       v
Calculate hash
       |
       v
Compress
       |
       v
Compare compressed and raw size
       |
       +---- Not worthwhile? ----> Store raw
       |
       v
Store encoded chunk
       |
       v
Generate metadata
```

An important optimization is compression fallback.

For example, when compressed data is not at least a configurable amount smaller than the original, store the original chunk.

Do not waste CPU and archive space compressing already-compressed PNG, JPEG, WebP, MP3, OGG, ZIP or similar content.

The final decision should be based on actual output size, not merely filename extensions.

## 5. Compression and hashing

I'd use a codec abstraction rather than hardwiring compression into the archive writer.

See the [Zstandard format specification](https://github.com/facebook/zstd/blob/dev/doc/zstd_compression_format.md).

**Zstandard (Zstd)**

Recommended default

Good general-purpose compression with a configurable speed/ratio tradeoff.

[LZ4 frame format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md).

**LZ4**

For latency-sensitive workloads and fast decompression.

[xxHash documentation](https://xxhash.com/).

**xxHash**

Fast content hashing and duplicate detection.

Recommended initial codec configuration:

| Configuration            | Setting           |
| ------------------------ | ----------------- |
| Default compression      | Zstd              |
| Default Zstd level       | 1–3               |
| Fast mode                | LZ4 frame         |
| No compression           | Raw               |
| Hashing                  | XXH3-128          |
| Security checksum        | SHA-256, optional |
| Minimum compression gain | Configurable      |

Zstd supports negative compression levels through its regular level interface, as well as reusable streaming contexts. Its documentation recommends one separate compression stream per thread.

XXH3-128 is useful for content identification, but it is not a cryptographic integrity mechanism. For untrusted or security-sensitive archives, add SHA-256 verification.

For LZ4, prefer its frame API when interoperability with other LZ4 tools matters.

## 6. Adapt the implementation to Goose's memory model

This is probably the most important part of the entire project.

Goose does not use a conventional general-purpose heap. Dynamic values are stored on compiler-managed data stacks. Resizable values grow in place, and their storage is released when the owning scope ends.

This is an excellent fit for a chunk-processing engine, provided you organize lifetimes correctly.

### Recommended memory strategy

| Data                           | Ownership            |
| ------------------------------ | -------------------- |
| Asset manifest                 | Main thread          |
| Chunk scheduling metadata      | Main thread          |
| Raw chunk buffer               | Worker-local scope   |
| Compressed chunk buffer        | Worker-local scope   |
| Hashing state                  | Worker-local scope   |
| Result metadata                | Bounded result queue |
| Archive index                  | Main thread          |
| Temporary serialization buffer | Writer-local scope   |

For example, conceptually:

```
fn process_chunk(job: ChunkJob) -> ChunkResult {
    // All temporary storage belongs to this operation.
    var raw: u8[>..] = [];
    var compressed: u8[>..] = [];

    // Read source bytes using native I/O.
    // Calculate checksum.
    // Compress into compressed.
    // Select raw or compressed representation.

    // Return a flat result.
}
```

The important principle is that intermediate arrays should not be accumulated in one application-wide array.

When the chunk-processing scope ends, its scratch allocations are released. The returned result has its own lifetime.

For example, with eight workers and a 1 MiB chunk size, the raw input buffers alone have a nominal working footprint of approximately 8 MiB, excluding compression buffers, queues, indexes and runtime overhead.

This is much easier to control than reading entire assets into memory.

## 7. Implement parallel processing using Goose threads

Goose has an unusual concurrency model:

- Workers are separate programs with their own data stacks.
- Mutable memory is not shared between workers.
- Workers communicate through typed queues.
- Messages must be flat values: they cannot contain references or slices.
- Flat variable-size data can be transferred as a single copied value.

These are language-level constraints, not merely recommendations.

That means you should design your jobs as self-contained values.

### Data structures

Here is the proposed model:

```
struct ChunkJob {
    sequence: u64,
    asset_id: u32,
    chunk_id: u32,
    file_handle: u64,
    source_offset: u64,
    raw_size: u32,
}

struct ChunkResult {
    sequence: u64,
    asset_id: u32,
    chunk_id: u32,

    raw_size: u32,
    stored_size: u32,

    codec: u8,
    hash_low: u64,
    hash_high: u64,

    // Variable-size, flat byte array.
    payload: u8[],
}
```

The file handle is an opaque token returned by the native I/O layer. It allows several workers to perform positional reads against the same source file, provided the C implementation uses thread-safe positional I/O rather than a shared seek position.

### Worker implementation

The actual compression and native I/O functions are implemented in the next section. The Goose worker control flow looks like this:

```
thread_fn compress_worker() {
    loop {
        let job = qget<ChunkJob>();

        // Reserved sentinel value.
        if job.sequence == 0xFFFF_FFFF_FFFF_FFFF {
            break;
        }

        let result = process_chunk(job);

        qput(result);
    }
}
```

You can spawn a fixed number of these workers:

```
fn start_workers() -> i64[>..] {
    let count = max(1, hardware_threads() - 1);

    qlimit<ChunkJob>(count * 2);
    qlimit<ChunkResult>(count * 2);

    var workers: i64[>..] = [];

    for i in count {
        workers.push(thread_spawn(compress_worker));
    }

    return workers;
}
```

The exact scheduler and result handling will be separate modules.

A few important details:

1. Use one worker per processing thread, not one thread per file or chunk.
2. Set bounded queue capacities and enforce a separate byte-based in-flight
   memory budget; a queue limit counts messages, not payload bytes.
3. Keep at most approximately `2 × worker_count` chunks in flight, subject to
   the byte budget and a bounded reorder buffer.
4. Give every chunk a deterministic sequence number.
5. Consume results in sequence order before committing them to the archive.

The last point matters. Workers finish at different times. Without sequence numbers, the archive's payload order could depend on scheduling, making reproducible builds much harder.

Goose's queue operations are nonblocking on insertion when a queue is full, so the scheduler must handle failed `qput` calls and maintain backpressure.

Implementation note: the snippet demonstrates the worker architecture. The `process_chunk` implementation, job producer, bounded in-flight scheduler and shutdown handling still need to be implemented.

## 8. Add a native I/O and compression layer

This is where I would make a deliberate exception to an otherwise Goose-only implementation.

The current Goose standard `os` module offers:

- `read_file`
- `write_file`
- `write_file_atomic`
- `append_file`
- `list_dir`
- `make_dir`
- `file_exists`

However, `read_file` reads the entire file into an array. The standard interface does not currently expose the persistent streaming file handles and positional reads needed by this design.

For the advanced implementation, build a small C backend.

**Goose application**

Asset discovery, archive format, scheduling, compression policies, indexes, validation

**Minimal C ABI**

File handles, positional I/O, atomic replacement, codec wrappers, optimized hashing

**Native libraries**

Zstandard

LZ4

xxHash

OS file APIs

### Native functions to expose

I'd start with this interface:

```
extern fn gp_open_read(path: const u8[:]) -> u64;

extern fn gp_file_size(handle: u64) -> u64;

extern fn gp_read_at(
    handle: u64,
    offset: u64,
    output: u8[:]
) -> i64;

extern fn gp_close(handle: u64);

extern fn gp_create_temp(path: const u8[:]) -> u64;

extern fn gp_write(
    handle: u64,
    data: const u8[:]
) -> i64;

extern fn gp_write_at(
    handle: u64,
    offset: u64,
    data: const u8[:]
) -> i64;

extern fn gp_flush(handle: u64);

extern fn gp_commit_replace(
    temporary_path: const u8[:],
    final_path: const u8[:]
) -> bool;
```

These declarations define the Goose side of a proposed C interface, not functions already supplied by Goose.

The C wrappers should use the compiler-generated Goose ABI types for slices. In particular, `u8[:]` crosses the C boundary as a data pointer and length pair. Goose also supports C builder parameters such as `u8[>..]&`, which allow a C function to append bytes to a Goose growable array.

### Compression interface

Keep the codec implementation behind a few more wrappers:

```
extern fn gp_zstd_compress(
    input: const u8[:],
    output: u8[>..]&,
    level: i32
) -> bool;

extern fn gp_lz4_compress(
    input: const u8[:],
    output: u8[>..]&
) -> bool;

extern fn gp_xxh3_128(
    input: const u8[:],
    low: u64&,
    high: u64&
);
```

The wrappers should:

- Reuse compression contexts per worker.
- Handle native allocation failures.
- Check every codec error.
- Never retain a Goose slice beyond its call.
- Return an explicit failure rather than silently producing invalid output.

The external C ABI is documented by Goose; a program can include its own C sources through its build configuration.

### Important optimization

Avoid crossing the C boundary for every byte or tiny operation.

Instead, read and compress substantial chunks in individual calls. Keep compression contexts alive across multiple chunks handled by the same worker.

The ideal arrangement is:

```
Goose worker
    |
    | one chunk
    v
Native positional read
    |
    v
Goose checksum / codec policy
    |
    v
Native compression
    |
    v
Goose chunk result
```

For even better throughput, you can eventually move the entire per-chunk read/hash/compress operation behind one C function. That reduces FFI transitions, but I would begin with the smaller interface so the format and scheduling logic remain easy to maintain in Goose.

## 9. Prevent the main writer from becoming a bottleneck

There are two sensible approaches.

**Approach A: bounded result messages**

Workers return compressed chunk contents through `qput`.

The main thread maintains a small pending-result array, writes results in sequence order, and updates the chunk table.

Advantages: straightforward, no temporary spool files.

Disadvantage: transferring large result arrays through queues adds memory-copy overhead.

**Approach B: per-worker temporary spool files**

Each worker writes encoded chunks to its own temporary spool and returns only metadata:

```
sequence
asset_id
chunk_id
worker_id
spool_offset
stored_size
raw_size
checksum
codec
```

The writer processes the metadata in deterministic order and copies the relevant ranges from worker spool files into the final archive.

Advantages: small messages and bounded queue payloads.

Disadvantages: extra file I/O, spool management and cleanup logic.

My provisional recommendation is to start with Approach A only if the scheduler
enforces both a bounded work window and a byte-based in-flight memory budget.
Queue capacity limits message counts, not aggregate payload bytes. The
coordinator must keep draining results while maintaining output order and
avoid waiting on an early sequence while later results fill the queue. Profile
this design; add Approach B if measurements show queue copies or memory
bandwidth are bottlenecks.

Do not introduce complexity before measurements justify it.

## 10. Proposed implementation structure

I'd organize it as follows:

```
gpack/
│
├── gpack.goose
├── gpack.build
│
├── src/
│   ├── cli.goose
│   ├── config.goose
│   │
│   ├── scanner.goose
│   ├── manifest.goose
│   ├── scheduler.goose
│   ├── worker.goose
│   │
│   ├── chunk.goose
│   ├── compression.goose
│   ├── hashing.goose
│   │
│   ├── archive_format.goose
│   ├── archive_writer.goose
│   ├── archive_reader.goose
│   ├── extractor.goose
│   │
│   ├── dedup.goose
│   ├── verifier.goose
│   └── errors.goose
│
├── native/
│   ├── gpack_io.c
│   ├── gpack_codec.c
│   └── gpack_native.h
│
├── tests/
│   ├── format_tests.goose
│   ├── compression_tests.goose
│   ├── corruption_tests.goose
│   ├── extraction_tests.goose
│   └── dedup_tests.goose
│
├── benchmarks/
│   ├── bench_pack.goose
│   ├── bench_extract.goose
│   └── datasets/
│
└── docs/
    ├── FORMAT.md
    ├── ARCHITECTURE.md
    └── BENCHMARKS.md
```

### Module responsibilities

| Module           | Responsibility                               |
| ---------------- | -------------------------------------------- |
| `scanner`        | Discover input files and directories         |
| `manifest`       | Keep sorted asset metadata                   |
| `scheduler`      | Generate chunk jobs and enforce backpressure |
| `worker`         | Coordinate parallel processing               |
| `chunk`          | Chunk boundaries and metadata                |
| `compression`    | Select and invoke codecs                     |
| `hashing`        | Hash calculation and comparisons             |
| `archive_format` | Binary encoding and decoding                 |
| `archive_writer` | Sequential output and finalization           |
| `archive_reader` | Archive inspection and random access         |
| `extractor`      | Safe file reconstruction                     |
| `dedup`          | Find and reuse existing chunks               |
| `verifier`       | Validate archive structure and integrity     |

A possible `gpack.build` file:

```
c_sources = [
    "native/gpack_io.c",
    "native/gpack_codec.c",
]
```

This is the intended Goose sidecar configuration pattern for adding your native implementation.

## 11. Implement advanced features

Once the basic packer works, these features will make it considerably more capable.

### A. Content-based deduplication

Instead of checking whether two filenames are identical, compare their content.

```
Asset A:
    Chunk 0 -> Hash A
    Chunk 1 -> Hash B
    Chunk 2 -> Hash C

Asset B:
    Chunk 0 -> Hash A
    Chunk 1 -> Hash D
    Chunk 2 -> Hash C
```

Store A, B, C and D once.

Both assets reference the corresponding stored chunks.

Your deduplication index can use:

```
hash -> candidate chunk records
```

A hash match is only a candidate match. Verify the actual bytes before reusing a chunk, so hash collisions cannot silently corrupt assets.

Benefits:

- Smaller archives.
- Faster incremental builds.
- Less repeated compression.
- Reuse of identical assets across projects.

### B. Incremental packing

Maintain an optional build cache:

```
source path
source size
modification timestamp
content hash
codec settings
chunk hashes
previous archive location
```

Use size and modification time as quick filters, not proof that content is unchanged.

When rebuilding, reuse unchanged chunks and only process changed content.

### C. Content-defined chunking

Fixed-size chunking is a good first implementation.

Later, implement content-defined chunking using a rolling hash.

Why?

Suppose a file changes near its beginning. With fixed-size chunking, many subsequent chunks can shift and appear different even though most of the content is unchanged.

Content-defined chunking identifies boundaries based on content rather than absolute offsets. This can substantially improve deduplication for modified large files.

I'd consider this a second-generation feature, not a requirement for v1.

### D. Memory-mapped extraction

For frequently accessed archives, implement an optional read-only memory-mapped backend in C.

This provides:

- Efficient random access.
- Reduced copying.
- Convenient access to the index.
- Potentially lower overhead when loading many small assets.

Keep positional reads as the portable baseline, with memory mapping as an optimization.

### E. Compression dictionaries

For collections of similar assets, support trained Zstd dictionaries.

Potential applications include:

- Similar JSON documents.
- Game configuration files.
- Textures with common data patterns.
- Repeated structured metadata.

Record the dictionary identifier and required dictionary metadata in the archive. Never assume an external dictionary is available without validating it.

## 12. Implement extraction and security properly

A good packer needs a good reader. Archive extraction is an important attack surface.

Your verifier should check:

| Check              | Purpose                                   |
| ------------------ | ----------------------------------------- |
| Magic and version  | Reject incompatible formats               |
| Header checksum    | Detect header corruption                  |
| Index bounds       | Prevent out-of-range reads                |
| Integer overflow   | Prevent invalid offset calculations       |
| Path normalization | Prevent traversal attacks                 |
| Duplicate paths    | Avoid ambiguous extraction                |
| Chunk boundaries   | Prevent overlapping or invalid references |
| Decompressed size  | Prevent decompression bombs               |
| Chunk checksum     | Detect corrupted payload                  |
| Codec identifier   | Reject unsupported codecs                 |

Particularly important:

**Never trust archive paths.**

Reject absolute paths, `..` traversal, embedded NULs and paths that escape the extraction root. Define an explicit symlink policy.

Use a safe path-joining implementation and, on POSIX, consider directory-relative operations with `openat` and `O_NOFOLLOW` to avoid symlink-based extraction escapes.

Also impose configurable limits on:

- Maximum asset count.
- Maximum path length.
- Maximum index size.
- Maximum decompressed asset size.
- Maximum compression ratio.
- Maximum chunks per asset.

For integrity, validate the reconstructed data rather than trusting metadata alone.

## 13. CLI design

I'd keep the interface familiar and script-friendly.

```
# Create an archive
gpack pack ./assets -o game.gpak

# Maximum compression
gpack pack ./assets -o game.gpak \
    --codec zstd \
    --level 9

# Fast packing
gpack pack ./assets -o game.gpak \
    --codec lz4 \
    --threads 8

# No compression
gpack pack ./assets -o game.gpak \
    --codec none

# Extract everything
gpack unpack game.gpak -o ./output

# Extract a specific asset
gpack extract game.gpak \
    textures/player.png \
    -o ./output

# List contents
gpack list game.gpak

# Inspect metadata
gpack inspect game.gpak

# Verify archive
gpack verify game.gpak

# Benchmark
gpack bench ./assets
```

Additional useful flags:

```
--chunk-size
--threads
--level
--deduplicate
--incremental
--exclude
--include
--follow-symlinks
--overwrite
--quiet
--verbose
--json
```

I'd ensure that JSON output is stable and suitable for build-system integration.

## 14. Performance engineering and benchmarking

Do not optimize based purely on intuition. Build a benchmark suite early.

### Benchmark datasets

| Dataset                | What it tests                            |
| ---------------------- | ---------------------------------------- |
| 100,000 tiny files     | Directory scanning and metadata overhead |
| 10,000 medium files    | Scheduling and compression throughput    |
| 100 files × 100 MB     | Parallel compression                     |
| One 10 GB file         | Streaming and large-file handling        |
| Pre-compressed assets  | Compression fallback                     |
| Duplicate-heavy assets | Deduplication                            |
| Random binary files    | Worst-case compression behavior          |

Measure:

1. Input throughput in MB/s.
2. Output throughput in MB/s.
3. Compression ratio.
4. Decompression throughput.
5. Peak resident memory.
6. CPU utilization.
7. Time spent in I/O.
8. Time spent hashing.
9. Time spent compressing.
10. Queue wait time and worker utilization.

On your Linux environment, useful profiling tools include:

```
perf stat ./gpack bench ./datasets/mixed

perf record -g ./gpack pack ./datasets/mixed -o /tmp/test.gpak

perf report

strace -c ./gpack pack ./datasets/mixed -o /tmp/test.gpak
```

Run tests both with warm filesystem caches and with appropriately controlled cold-cache conditions.

### Optimization priorities

I'd work through these in order:

1. Eliminate unnecessary memory allocations and copies.
2. Implement buffered positional file I/O.
3. Reuse compression contexts.
4. Keep worker queues bounded.
5. Tune chunk sizes.
6. Optimize metadata lookup and deduplication.
7. Reduce unnecessary syscalls.
8. Investigate SIMD hashing and compression.
9. Experiment with memory mapping.
10. Optimize archive index lookup.

One additional optimization: avoid treating thousands of tiny files as thousands of independent expensive compression operations. Batch small-file processing where practical, while preserving per-asset metadata and extraction semantics.

## 15. Proposed development roadmap

Don't implement all the advanced features simultaneously.

1. **Phase 1 — Working archive format**
   - Define the binary format.
   - Implement binary serialization.
   - Implement single-threaded pack/unpack.
   - Implement listing and verification.
   - Test corrupted inputs.

   Foundation
2. **Phase 2 — Native performance**
   - Implement C streaming I/O.
   - Integrate Zstd.
   - Integrate LZ4.
   - Integrate XXH3.
   - Implement raw-storage fallback.
3. **Phase 3 — Parallel processing**
   - Add Goose worker functions.
   - Implement bounded queues.
   - Add chunk scheduling.
   - Add deterministic result ordering.
   - Add worker error handling.
4. **Phase 4 — Advanced storage**
   - Chunk deduplication.
   - Incremental builds.
   - Compression dictionaries.
   - Content-defined chunking.
   - Read-only memory mapping.
5. **Phase 5 — Production hardening**
   - Cross-platform compatibility.
   - Archive fuzzing.
   - Malformed archive handling.
   - Atomic archive replacement.
   - Crash recovery.
   - Performance regression tests.
   - Format documentation.

## 16. Open format detail

The magic value is unresolved in this draft. The earlier header example
conflicted with its stated eight-byte size, so choose and document an exact
eight-byte signature before freezing the format.

The worker-ID return type must match the growable array returned by the
implementation:

```
fn start_workers() -> i64[>..] {
    // ...
}
```

Verify this signature against the Goose compiler version in use when
implementation begins.

## 17. Proposed technology stack (unvalidated)

### Recommended GPACK stack

| **Implementation language** | Goose                        |
| --------------------------- | ---------------------------- |
| **Native backend**          | C                            |
| **Compression**             | Zstandard + LZ4              |
| **Hashing**                 | XXH3-128 + optional SHA-256  |
| **Memory management**       | Goose data stacks            |
| **Concurrency**             | Goose typed queues           |
| **File I/O**                | Native streaming backend     |
| **Binary format**           | Custom little-endian format  |
| **Build system**            | Goose compiler + C toolchain |
| **License strategy**        | FOSS dependencies            |

**Useful primary documentation**

- [Goose language reference](https://aardappel.github.io/goose/docs/reference.html)
- [Goose language specification](https://aardappel.github.io/goose/docs/goose_spec.html)
- [Goose standard library](https://aardappel.github.io/goose/docs/stdlib.html)
- [Zstandard API manual](https://facebook.github.io/zstd/doc/api_manual_latest.html)
- [LZ4 frame format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md)
- [XXHash documentation](https://xxhash.com/)

## Current recommendation

Build GPACK as a **Goose-first systems application with a deliberately small C backend**.

Keep the archive format, asset processing policies, job scheduling, indexing, deduplication, and verification in Goose. Delegate only the operations where native APIs or mature native libraries provide a clear advantage.

The first meaningful milestone should be a working, streaming, single-threaded GPACK v1. Then add parallel chunk processing without changing the archive format.

This gives you a maintainable foundation rather than a complicated compression benchmark that happens to produce binary files.
