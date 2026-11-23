# Design the repository and build foundation

Type: grilling
Status: resolved
Blocked by: 01, 03, 04, 06

## Question

Define a repository layout and build/test/release workflow that keep the Goose
policy layer and any native backend connected through one authoritative
contract. Decide module boundaries, generated/shared format definitions,
dependency pinning, supported compiler/platform matrix, test fixtures,
benchmark placement, lint/static checks, and how changes propagate to all
callers without duplicated definitions. Specify a clean start-state file tree.

## Answer

Keep one Goose package for the public library, format policy, packer, reader,
and verifier, with a thin CLI executable importing that package. The Goose
package is the sole parser and writer of the on-disk format. Maintain one
normative v1 format document and golden fixtures; native code must not parse
or emit GPack records. Keep the native seam to file I/O and Zstandard. Define
that ABI in one C header included by the native sources and Goose-generated C
through the package build sidecar, so mismatched declarations fail compilation.

Pin Goose v2026.4 and build the vendored Zstandard 1.5.7 source as a static
native target through the Goose `.build` CMake integration. Use native builds
on Linux with GCC, macOS with Apple Clang, and Windows with MSVC. Do not claim
cross-platform byte identity until golden-output checks pass on all three.

### Proposed clean start tree

```text
cmd/gpack.goose                 # CLI entrypoint; imports ../src/gpack
src/gpack/gpack.goose           # public library package
src/gpack/{format,paths,pack,reader,verify}.goose
src/gpack/gpack.build           # builds the static native target
src/gpack/CMakeLists.txt        # I/O adapter + pinned Zstandard target
src/gpack/native/gpack_native.h # shared, checked Goose/C ABI declarations
third_party/zstd-1.5.7/         # upstream source and license notices
tests/*.goose                   # integration executables against the package
tests/fixtures/                 # small golden archives and malformed variants
scripts/                        # format, check, build, and test entrypoints
docs/product/spec.md            # product contract
docs/format/v1.md               # normative on-disk contract
docs/research/experiments/      # manual, reproducible performance studies
```

The format document owns wire-field definitions. `format.goose` implements
them; golden fixtures exercise both reads and writes. The C header owns only
the native ABI. Do not generate duplicate C format structs or Goose format
declarations.

### Validation and release workflow

- `scripts/format` runs `goose format` and checks for a clean diff.
- `scripts/check` runs `goose check` for the library, CLI, and each test root,
  plus C static warnings on the native target.
- `scripts/test` builds native executables and runs round-trip, golden archive,
  raw/Zstandard, corruption, malformed-path/range, size-limit, and concurrent
  read fixtures. CI runs these on native Linux/GCC, macOS/Apple Clang, and
  Windows/MSVC workers; `goose run` is not a substitute for threaded tests.
- Keep performance benchmarks under `docs/research/experiments/`; run them
  manually because shared CI timing is noisy. Do not make benchmark throughput
  a release gate.
- Cut releases from version tags only after the full platform correctness
  matrix passes. Ship codec license notices with source and binaries.

The repository host is not configured yet, so keep the build/test entrypoints
provider-neutral; the selected CI service can invoke them without duplicating
the build logic.
