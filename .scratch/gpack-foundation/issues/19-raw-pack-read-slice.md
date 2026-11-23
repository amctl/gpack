# Deliver the raw pack/read vertical slice

Type: task
Status: resolved
Blocked by: 18

## Goal

Implement a deterministic raw-only `pack` path and runtime complete-asset read
using the v1 index and native positional I/O. This is the first end-to-end
product slice, not a new format.

## Acceptance

- `gpack pack INPUT_DIR OUTPUT.gpk` and the Goose runtime API can round-trip
  empty, small, and boundary-sized raw assets.
- Output order and bytes are deterministic for identical paths and content.
- One open archive supports four concurrent positional reads.
- Tests cover path lookup, not-found errors, size limits, and source mutation
  detection where the platform exposes it.

## Answer

Added the native positional file API for regular-file open, size/stamp, read,
write, flush, and close. POSIX uses `pread`/`pwrite`; Windows uses overlapped
I/O. Goose now walks input trees, rejects symlinks and non-regular entries,
sorts canonical asset paths, streams raw payloads in 1 MiB chunks, computes
content CRC32, checks size and modification stamp after reading, and writes
the validated header/index. The runtime opens and validates the index, reads
complete raw assets by path, enforces the configured read limit, and offers
flat read requests for four concurrent Goose workers on one handle. The CLI
now implements `gpack pack INPUT_DIR OUTPUT.gpk`.

Round-trip coverage includes empty, small, and 1 MiB + 1 byte assets,
deterministic output, path lookup and not-found, size limits, source mutation
detection, and four concurrent positional reads.

Goose format/type checks passed. The format test passed. The full pack/read
test and CLI pack command passed on Linux using a temporary validation copy
that compiled the same native source against the host's installed Zstandard
library; the repository remains configured to build vendored Zstandard 1.5.7
statically through CMake. Strict GCC compilation and a native positional-I/O
probe passed, as did generated C ABI compilation and `git diff --check`. The
full pinned CMake build and macOS/Windows CI results remain for the matrix;
this host has no C++ compiler.
