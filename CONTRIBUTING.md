# Contributing to gpack

Thank you for contributing to `gpack`!

## Toolchain Requirements

- **Goose** `v2026.4` (tag `v2026.4` as pinned in [`.github/workflows/ci.yml`](.github/workflows/ci.yml))
- **CMake** (`>= 3.16`)
- **C/C++ compiler**: GCC/G++ on Linux, Apple Clang on macOS, MSVC on Windows
- **Python 3** (`>= 3.10`)

## Development Workflow

All formatting, type-checking, building, and testing go through [`scripts/gpack.py`](scripts/gpack.py):

```sh
# Format Goose sources
python scripts/gpack.py format

# Format-check and Goose type-check all targets
python scripts/gpack.py check

# Build CLI + test binaries and verify static Zstandard linkage & notices
python scripts/gpack.py build

# Run ABI, format v1, end-to-end pack/read, and CLI test suites
python scripts/gpack.py test

# Run the complete CI pipeline (check + build + test)
python scripts/gpack.py ci
```

If using a local compiler binary or custom Goose home directory:

```sh
GOOSE=./goose-bin/goose GOOSE_HOME=/tmp/gpack-goose-home python scripts/gpack.py ci
```

## Architecture & Format Contracts

- **Goose owns format semantics; C owns I/O & Zstandard only.** Keep parsing, path normalization, ordering, CRC32, and validation in `src/gpack/*.goose`. Do not teach `src/gpack/native/` about gpack headers or index records.
- **Keep the native ABI aligned.** Any signature change in `src/gpack/gpack.goose` must match `src/gpack/native/gpack_native.h` and `src/gpack/native/abi_probe.c` (compiled with `-Wall -Wextra -Werror` / `/W4 /WX`).
- **Format changes require a versioned update.** Update [`docs/format/v1.md`](docs/format/v1.md), `src/gpack/format.goose`, golden fixtures under `tests/fixtures/`, and version checks together.
- **No dynamic `libzstd` dependency.** `scripts/gpack.py build` enforces static Zstandard `1.5.7` linkage across all executables.
- **Canonical vocabulary.** Follow [`GLOSSARY.md`](GLOSSARY.md) in code, docs, and issues.

## Benchmarks & Research

Benchmarks are manual and live under [`docs/research/experiments/`](docs/research/experiments/). Do not add noisy wall-clock throughput gates to PR CI. Keep corpus assets out of git (use SHA-256 manifests).

## Releases

See [`docs/release.md`](docs/release.md) for the tagged release checklist and platform matrix requirements.
