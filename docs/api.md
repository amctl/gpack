# Goose Library API Reference

The `gpack` package lives under `src/gpack/` and exposes four modules:

- `gpack` — package version metadata and native ABI wrappers.
- `gpack.format` — normative v1 header/index encoding, decoding, validation, CRC32, and path rules.
- `gpack.pack` — deterministic directory scanning, compression/raw selection, mutation detection, and atomic archive output.
- `gpack.reader` — read-only archive handles, concurrent positional reads, listing, and verification.

Import the package from a Goose source file relative to `src/gpack`:

```goose
import gpack from "../src/gpack";
import gpack.format;
import gpack.pack;
import gpack.reader;
```

## `gpack`

### Constants & Functions

- `VERSION: const u8[:]` — package version string (`"1.0.0"`).
- `FORMAT_MAJOR: u16` — v1 major format version (`1`).
- `FORMAT_MINOR: u16` — v1 minor format version (`0`).
- `fn zstd_version() -> u32` — returns the linked Zstandard version integer (e.g. `10507` for `1.5.7`).

## `gpack.format`

Pure-Goose implementation of the [v1 binary format](format/v1.md).

### Constants

- `HEADER_SIZE: i64` (`64`)
- `MAX_ENTRIES: u64` (`1000000`)
- `MAX_INDEX_SIZE: u64` (`64 * 1024 * 1024`)
- `MAX_ASSET_SIZE: u64` (`8 * 1024 * 1024 * 1024`)
- `RAW: u8` (`0`)
- `ZSTD: u8` (`1`)

### Types

```goose
struct Header {
    entry_count:  u64,
    index_offset: u64,
    index_size:   u64,
    index_crc32:  u32,
}

struct Entry {
    path:              const u8[:],
    codec:             u8,
    uncompressed_size: u64,
    payload_offset:    u64,
    stored_size:       u64,
    content_crc32:     u32,
}
```

### Functions

- `fn crc32(data: const u8[:]) -> u32` — computes IEEE CRC32 of `data`.
- `fn crc32_update(state: u32, data: const u8[:]) -> u32` — incremental CRC32 step (start with `0xffffffff`, finish with `~state`).
- `fn crc32_header(data: const u8[:]) -> u32` — computes header CRC32 with bytes `44..48` zeroed.
- `fn valid_utf8(data: const u8[:]) -> bool` — RFC 3629 UTF-8 validation.
- `fn valid_path(path: const u8[:]) -> bool` — validates canonical asset path (`1..4096` UTF-8 bytes, relative `/`-separated, no NUL, `\`, leading/trailing `/`, empty components, `.` or `..`).
- `fn path_less(a: const u8[:], b: const u8[:]) -> bool` — unsigned lexicographic byte comparison.
- `fn encode_header(header: Header) -> u8[>..]` — serializes a 64-byte v1 header with header CRC32.
- `fn decode_header(data: const u8[:], file_size: u64) -> Header, bool` — validates magic, version, sizes, reserved bytes, bounds, and header CRC32.
- `fn encode_index(entries: const Entry[:]) -> u8[>..], bool` — validates and serializes sorted index records.
- `fn decode_index(data: const u8[:], header: Header, entries: Entry[>..]&) -> bool` — verifies index CRC32, parses records, and validates paths, codecs, and non-overlapping payload ranges.
- `fn validate_entries(entries: const Entry[:], index_offset: u64) -> bool` — validates ordering, uniqueness, codec invariants, and payload range bounds.

## `gpack.pack`

### Types

```goose
struct PackSummary {
    entry_count:        u64,
    raw_count:          u64,
    zstd_count:         u64,
    empty_count:        u64,
    uncompressed_bytes: u64,
    stored_bytes:       u64,
    archive_bytes:      u64,
}
```

### Functions

- `fn pack_directory(input_dir: const u8[:], output_path: const u8[:]) -> bool`
  Packs regular files from `input_dir` into `output_path` atomically. Rejects symlinks, non-regular entries, unsafe/duplicate paths, and detected source file mutations. Compresses non-empty files with Zstandard `1.5.7` level 3 and falls back to `raw` if the frame is not smaller.
- `fn pack_directory_detailed(input_dir: const u8[:], output_path: const u8[:], summary: PackSummary&, error: u8[>..]&) -> bool`
  Same behavior as `pack_directory`, populating `summary` on success or an actionable diagnostic message in `error` on failure.

## `gpack.reader`

### Constants

- `DEFAULT_MAX_ASSET_SIZE: u64` (`32 * 1024 * 1024`, 32 MiB)
- `SMALL_FRAME_ONE_SHOT_MAX: u64` (`1024 * 1024`, 1 MiB)

### Types

```goose
struct RuntimeEntry {
    path_start:        i64,
    path_len:          i64,
    codec:             u8,
    uncompressed_size: u64,
    payload_offset:    u64,
    stored_size:       u64,
    content_crc32:     u32,
}

struct ArchiveInfo {
    format_major:       u16,
    format_minor:       u16,
    file_size:          u64,
    entry_count:        u64,
    index_offset:       u64,
    index_size:         u64,
    index_crc32:        u32,
    raw_count:          u64,
    zstd_count:         u64,
    empty_count:        u64,
    uncompressed_bytes: u64,
    stored_bytes:       u64,
}

struct ReadRequest {
    handle:         u64,
    payload_offset: u64,
    size:           u64,
    stored_size:    u64,
    content_crc32:  u32,
    codec:          u8,
    ticket:         u64,
}

struct ReadResult {
    ticket: u64,
    ok:     bool,
    bytes:  u8[],
}

root struct Archive { ... }
```

### Lifecycle & Lookup

- `fn open(path: const u8[:], archive: Archive&, max_asset_size: u64 = DEFAULT_MAX_ASSET_SIZE) -> bool`
  Opens `path` read-only, validates the header and complete index, and stores the validated entry table in `archive`. `max_asset_size` caps per-asset read allocations.
- `fn open_detailed(path: const u8[:], archive: Archive&, max_asset_size: u64, error: u8[>..]&) -> bool`
  Like `open`, populating `error` on failure.
- `fn close(archive: Archive&)`
  Closes the underlying native handle and clears metadata. Keep `archive` open until all spawned `read_worker` threads complete.
- `fn count(archive: Archive&) -> i64` — returns the number of entries in `archive`.
- `fn find(archive: Archive&, path: const u8[:]) -> i64` — binary-searches canonical `path`; returns entry index or `-1`.
- `fn contains(archive: Archive&, path: const u8[:]) -> bool` — returns whether canonical `path` exists in `archive`.
- `fn path_at(archive: Archive&, index: i64) -> const u8[:]` — returns the canonical path slice at `index` (empty slice if out of range).
- `fn entry_at(archive: Archive&, index: i64) -> RuntimeEntry, bool` — returns entry metadata at `index`.
- `fn info(archive: Archive&) -> ArchiveInfo` — aggregates archive header and codec/byte totals.

### Reading & Verification

- `fn read(archive: Archive&, path: const u8[:], out: u8[>..]&) -> bool`
  Synchronously reads, decodes (strictly one Zstandard frame or raw), and CRC32-verifies the complete asset into `out`.
- `fn request(archive: Archive&, path: const u8[:], ticket: u64 = 0) -> ReadRequest, bool`
  Resolves `path` and enforces `max_asset_size` into a flat `ReadRequest` safe to pass across Goose worker queues.
- `fn read_request(request: ReadRequest, out: u8[>..]&) -> bool`
  Executes a `ReadRequest` using positional I/O (`pread` on POSIX, overlapped `ReadFile` on Windows) without mutating shared archive state.
- `thread_fn read_worker(request: ReadRequest)`
  Worker entrypoint that runs `read_request` and sends `ReadResult` back via `qput`.
- `fn list(path: const u8[:]) -> bool`
  Opens `path`, validates header and index, and writes `<path> <stored_size> <uncompressed_size>` lines to `stdout`.
- `fn verify(path: const u8[:], max_asset_size: u64 = DEFAULT_MAX_ASSET_SIZE) -> bool`
  Validates header/index and verifies every asset using up to 4 concurrent `read_worker` threads.
- `fn verify_detailed(path: const u8[:], workers: i64, max_asset_size: u64, verified_count: u64&, total_bytes: u64&, failed_path: u8[>..]&, error: u8[>..]&) -> bool`
  Concurrent verification (`1..16` workers) returning verified counts and the failing `failed_path` / `error` on failure.

### Concurrent Reads Example

```goose
var archive = reader::Archive { .. };
assert(reader::open("assets.gpk", archive));

let r0, ok0 = reader::request(archive, "a.bin", 0);
let r1, ok1 = reader::request(archive, "b.bin", 1);
assert(ok0 && ok1);

qlimit<reader::ReadResult>(4);
let h0 = thread_spawn(reader::read_worker, r0);
let h1 = thread_spawn(reader::read_worker, r1);

for _ in 2 {
    let res = qget<reader::ReadResult>();
    assert(res.ok);
    // handle res.ticket and res.bytes
}

thread_wait(h0);
thread_wait(h1);
reader::close(archive);
```

### Memory Budget

`max_asset_size` (32 MiB default) bounds the uncompressed allocation of a single read. With `N` concurrent workers (4 by default), in-flight working memory scales as `O(N * max_asset_size)` plus any decoded asset buffers retained by the caller and the archive index (capped at 64 MiB by format v1).
