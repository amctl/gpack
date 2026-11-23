# Add Zstandard, raw fallback, listing, and verification

Type: task
Status: resolved
Blocked by: 19

## Goal

Integrate pinned Zstandard 1.5.7 at level 3 with frame checksums, select raw
storage when a frame does not reduce size, and complete the v1 CLI with `list`
and `verify`.

## Acceptance

- Compressed assets use exactly one independent frame; raw fallback is marked
  in each index record.
- Every asset CRC32 and header/index CRC32 is generated and validated.
- `list` validates metadata without decoding payloads; `verify` decodes every
  asset and checks both integrity mechanisms.
- Fixtures cover raw, compressed, empty, incompressible, corrupted, and
  concatenated/trailing-frame cases.

## Answer

Implemented the Goose-owned streaming Zstandard 1.5.7 level-3 writer and
reader, per-asset CRC32, raw fallback when compression is not smaller, and
`list`/`verify` CLI commands. The reader requires one complete frame consuming
the full stored extent and producing the declared size. Added fixtures for
compressed/raw/empty assets, corruption of both codecs, trailing and
concatenated frames, determinism, concurrency, and the runtime size cap.

Validation: Goose format and type checks passed; native C compiled with
`-Wall -Wextra -Werror` against the vendored Zstandard headers; the pack/read
end-to-end test passed using the host's dynamic `libzstd`; CLI `list` and
`verify` passed on that archive. This host lacks a C++ compiler, so the
production pinned static CMake link and the three-platform CI matrix remain
unverified and are tracked by issue 23.
