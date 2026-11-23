# Handoff: continue GPack issue 22

## Completion update (2026-11-24)

Issue 22 is resolved. The product v1 benchmark met the median 10% throughput
gate on the measured Linux build. See
`docs/research/experiments/v1-runtime-throughput/results.md`; issue 23 is now
the next action. The notes below preserve the context that was current when
this handoff was created.

This note captures the implementation state and the next work for a new agent.

## Current objective

Continue `.scratch/gpack-foundation/issues/22-runtime-throughput-acceptance.md`.
It is `Status: claimed`, not resolved. The goal is a production-shaped v1 Goose
runtime benchmark against a C reference, then reduce overhead and remeasure.

Acceptance requires five paired runs over byte-identical product v1 archives
for the Godot-real and mixed workloads; throughput within 10% of C on both (or
an explicit product requirement revision before release); correctness,
malformed-input rejection, p50/p95 latency, peak RSS, and remeasurement of the
four-reader/32 MiB defaults. If performance remains outside the gate, record
the decision and keep runtime performance explicitly unaccepted.

## Recent issue status

- Issues 17–19 were already resolved before this turn.
- Issue 20 is resolved: Zstandard 1.5.7 level 3, frame checksums, per-asset
  CRC32, raw fallback, strict one-frame reads, and `list`/`verify`.
- Issue 21 is resolved: input validation, configurable runtime asset limit,
  sibling temporary output, flush/close/atomic replace, cleanup on failure,
  and a fixture for source mutation preserving an existing destination.
- Issue 22 is claimed and incomplete.
- Issue 23 remains for cross-platform CI/release validation.

The next-action pointer in `docs/research/state.yaml` points to issue 22.
`README.md` describes performance and cross-platform release validation as
remaining.

## Changes made in the current turn

Issue 21 implementation added native APIs in `src/gpack/gpack.goose`,
`src/gpack/native/gpack_native.h`, and `src/gpack/native/abi_probe.c` for
exclusive file creation, a process/counter nonce, atomic replacement, and
temporary-file removal. `src/gpack/pack.goose` writes to an exclusive sibling
temporary file, removes it on every handled failure, and replaces the output
only after the archive has been written and flushed. It also rejects duplicate
asset paths after sorting.

`tests/pack_read.goose` now exercises source mutation during directory packing,
preservation of an existing output, and temporary-file cleanup. The test also
covers v1 compression/raw behavior, payload corruption, one-frame enforcement,
four concurrent reads, and runtime size caps.

Issue 22 work started with a CRC32 nibble-table implementation in
`src/gpack/format.goose`. Format vectors and the end-to-end pack/read fixture
pass. Its throughput effect has **not** been measured; keep it only if a
product-shaped benchmark shows it helps or at least does not regress.

Issue files/map/status were updated in `.scratch/gpack-foundation/`, and
`README.md` plus `docs/research/state.yaml` were updated after issue 21.

## Important benchmark limitation

The historical H3 benchmark in
`docs/research/experiments/h3-runtime-lookup/` is not a valid issue 22 result:
it constructs an H2 archive and measures a separate prototype Goose reader.
Its recorded 27.4% Godot-real and 12.1% mixed gaps motivate issue 22, but do
not measure the current product v1 implementation. The old C reference also
understands H2 only. Do not cite an H3 rerun as product v1 evidence.

The corpus is present at `/tmp/gpack-corpus-godot-4.7` in this environment,
with `2d/kinematic_character`, `3d/lights_and_shadows`, and `audio/mic_record`.
The H3 benchmark helpers can be inspected for workload construction and
measurement conventions, especially `bench.py` and the results/protocol files.
Build a product-shaped benchmark and v1 C reference before making performance
claims. Preserve paired order, identical archive bytes, five runs, correctness
checks, latency, RSS, and workload metadata.

## Validation already run

Passed:

- `./goose-bin/goose format --check cmd src/gpack tests`
- Goose checks for `cmd/gpack.goose`, `tests/native_abi.goose`,
  `tests/format_v1.goose`, and `tests/pack_read.goose`
- `gcc -std=c11 -Wall -Wextra -Werror -I third_party/zstd-1.5.7/lib -c src/gpack/native/abi_probe.c -o /tmp/gpack-abi-probe.o`
- `git diff --check`
- Local pack/read end-to-end test, including the mutation and atomic-output
  fixture
- Local CLI `list`, `verify`, and `pack` against a test archive

The local end-to-end build used the host's dynamic `libzstd`, not the
production pinned static CMake linkage. It ran in `/tmp/gpack-local`, whose
temporary `src/gpack/gpack.build` override was:

```text
c_sources = ["native/abi_probe.c"];
c_include = ["../../third_party/zstd-1.5.7/lib"];
c_libs_linux = ["zstd"];
c_headers = ["native/gpack_native.h"];
```

Run from `/tmp/gpack-local` with:

```sh
GOOSE_HOME=/tmp/gpack-local/goose-home \
  /home/amctl/projects/gpack/goose-bin/goose build \
  /tmp/gpack-local/tests/pack_read.goose -o /tmp/gpack-local/pack_read
./pack_read
```

The repository checkout's production build uses CMake/static Zstandard. This
host lacked a C++ compiler, so the pinned static linkage was not verified.
`goose-bin/` is ignored research/toolchain input: do not modify it.

## Suggested next steps

1. Read `.scratch/gpack-foundation/issues/22-runtime-throughput-acceptance.md`,
   `docs/product/spec.md`, `docs/product/architecture.md`,
   `docs/format/v1.md`, and `GLOSSARY.md`.
2. Inspect the H3 benchmark protocol and harness, but adapt them to the
   production v1 `reader` API and v1 archives. Add a Goose benchmark driver
   exercising four concurrent complete-asset reads and a C reference reader
   that validates the same v1 archive/CRC semantics.
3. Use product `pack` to create identical v1 archives for the Godot-real and
   mixed workloads. Recheck malformed inputs, content correctness, p50/p95,
   and RSS. Explicitly exercise the default 32 MiB cap and the chosen override
   for any mixed workload asset above that cap.
4. Establish five paired runs before making more hot-path changes. Test one
   hypothesis at a time. The current ranked candidates were queue/result-copy
   overhead, Goose CRC32 cost, streamed Zstandard call overhead, and per-read
   I/O/scheduling overhead.
5. Keep the `docs/research/state.yaml` and issue 22 status accurate. If the
   gate remains unmet, record the design decision without claiming runtime
   performance acceptance. Do not mark issue 22 resolved without its required
   benchmark report.

## Workspace note

The checkout has a large pre-existing set of untracked and deleted files from
the repository bootstrap/research work. Do not clean or reset the tree. The
ignored `goose-bin/` toolchain and `/tmp/gpack-local` validation copy are
environment inputs, not deliverables.
