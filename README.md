# gpack

**gpack** is a deterministic, versioned binary asset archive format, CLI tool, and Goose runtime library built for game and runtime assets with fast random-access asset reads.

- **Deterministic builds:** Sorted canonical UTF-8 paths, omitted host timestamps/permissions, pinned Zstandard `1.5.7` (level 3) with automatic raw fallback, and sibling-temp atomic output replacement.
- **Safe & verified:** Rejects symlinks, non-regular entries, traversal/invalid paths, duplicate canonical paths, and source mutations during packing; checks header, index, per-asset IEEE CRC32, and Zstandard frame checksums on read.
- **Concurrent runtime lookup:** Read-only archive handles with positional I/O (`pread` / overlapped Win32 I/O) supporting lock-free concurrent full-asset reads and configurable per-asset memory limits (default 32 MiB, 4 workers).
- **Self-contained native build:** Static vendored Zstandard `1.5.7` via CMake with zero dynamic `libzstd` runtime dependency.

## Quick Start

### Prerequisites

- **Goose** `v2026.4` (pinned commit `dec4bd827a1da10041febd7eb583fe3c4f96a2b9`)
- **CMake** (`>= 3.16`) and a C/C++ compiler (`gcc`/`g++` on Linux, Apple Clang on macOS, MSVC on Windows)
- **Python 3** (`>= 3.10`) for build and CI orchestration

### Build and Test

```sh
# Run format checks, Goose type-checks, CMake static build, linkage checks, and all tests
python scripts/gpack.py ci
```

If `goose` is not on your `PATH`, pass `GOOSE=/path/to/goose`:

```sh
GOOSE=./goose-bin/goose python scripts/gpack.py ci
```

This builds the CLI binary at `build/gpack` (or `build/gpack.exe` on Windows) and copies Zstandard third-party notices to `build/THIRD_PARTY_NOTICES/`.

## CLI Usage

```text
gpack <command> [options] [args...]
```

| Command | Description |
|---|---|
| `pack` | Recursively pack regular files from a directory into a deterministic `.gpk` archive |
| `list` (`ls`) | Validate metadata and list entries (`--long` table or `--json`) without decoding payloads |
| `info` | Inspect archive header, codec breakdown, index CRCs, and size totals (`--json`) |
| `verify` | Decode and verify every asset (Zstandard frame + CRC32) using concurrent workers |
| `read` (`cat`) | Read and verify a single asset by canonical path and write bytes to `stdout` |
| `version` | Print `gpack`, format, and Zstandard versions |
| `help` | Show global or per-command help |

### Examples

```sh
# Pack an asset directory with summary output
gpack pack --verbose assets/ game.gpk

# Inspect archive metadata
gpack info game.gpk

# List entries as a formatted table or JSON
gpack list --long game.gpk
gpack list --json game.gpk

# Verify all assets with 4 concurrent workers and a 64 MiB per-asset cap
gpack verify --verbose --jobs 4 --max-size 64M game.gpk

# Read a single asset directly to stdout without extracting to disk
gpack read game.gpk textures/player.png > player.png
```

See the full [CLI Reference](docs/cli.md) for all flags, size suffixes, JSON schemas, and exit codes.

## Goose Library API

Import `gpack` modules from your Goose project (`import gpack from ".../src/gpack"`):

```goose
import gpack from "../src/gpack";
import gpack.pack;
import gpack.reader;
import os;

fn main() {
    // Pack a directory deterministically
    var summary = pack::PackSummary { 0, 0, 0, 0, 0, 0, 0 };
    var err: u8[>..] = [];
    assert(pack::pack_directory_detailed("assets", "assets.gpk", summary, err));

    // Open read-only and read a complete asset by canonical path
    var archive = reader::Archive { .. };
    assert(reader::open("assets.gpk", archive));

    var data: u8[>..] = [];
    assert(reader::read(archive, "textures/player.png", data));

    reader::close(archive);
}
```

For concurrent 4-worker reads (`reader::request` + `reader::read_worker`), format primitives, and error diagnostics, see the [Goose API Reference](docs/api.md).

## Archive Format & Guarantees

- **Normative layout:** `64-byte header | payload region | entry index` ([format v1](docs/format/v1.md)).
- **Integrity boundary:** IEEE CRC32 (header, index, and per-asset uncompressed bytes) plus Zstandard frame content checksums detect accidental corruption. They do **not** provide cryptographic authenticity or tamper resistance.
- **V1 scope:** Designed for build-time packing and read-only runtime asset lookup. V1 intentionally omits filesystem extraction, byte-range reads, deduplication, incremental patching, and mounting.

## Platform Support

| Platform | Compiler | Codec | Status |
|---|---|---|---|
| Linux (`ubuntu-24.04`) | GCC | Static Zstandard `1.5.7` | Verified |
| macOS (`macos-14`) | Apple Clang | Static Zstandard `1.5.7` | **WIP** (CI matrix configured; pending hosted runner validation) |
| Windows (`windows-2022`) | MSVC | Static Zstandard `1.5.7` | **WIP** (CI matrix configured; pending hosted runner validation) |

## Project Status & Evidence

- **Implemented & Linux-verified:** Format v1 primitives, deterministic packing, streaming/one-shot Zstandard `1.5.7` with raw fallback, `list`/`info`/`verify`/`read` CLI, input safety, atomic output, and `python scripts/gpack.py ci` pass on Linux (`ubuntu-24.04` / GCC).
- **Throughput & ZIP comparison:**
  - The [v1 runtime throughput gate](docs/research/experiments/v1-runtime-throughput/results.md) and [127 MiB Material Testers run](docs/research/experiments/v1-runtime-throughput/results-larger-corpus.md) met the 10% median throughput target vs. C on the measured Linux host.
  - The [restricted ZIP comparison](docs/research/experiments/restricted-zip-comparison/results.md) measured a small raw-container size advantage for `gpack` and workload-dependent Zstandard vs. DEFLATE tradeoffs (no general format winner claimed; results are scoped to the measured Linux workloads).
- **Open release gate ([issue 23](.scratch/gpack-foundation/issues/23-platform-release-gate.md)):** Native `macos-14` (Apple Clang) and `windows-2022` (MSVC) GitHub Actions matrix runs and cross-platform golden-archive byte-identity checks remain to be verified on hosted CI runners before tagging a release.

## Documentation Map

- [CLI Reference](docs/cli.md) — commands, options, size syntax, JSON output, and exit codes.
- [Goose API Reference](docs/api.md) — public structs, functions, concurrency pattern, and memory limits.
- [V1 Product Specification](docs/product/spec.md) — accepted contract, path rules, and limits.
- [V1 Format Contract](docs/format/v1.md) — normative binary layout and validation rules.
- [V1 Architecture](docs/product/architecture.md) — module boundaries, data flow, and source tree.
- [Risk Register](docs/product/risks.md) — open acceptance gates and operational mitigations.
- [Release Procedure](docs/release.md) — tag and platform-validation steps.
- [Contributing Guide](CONTRIBUTING.md) — build, formatting, testing, and research workflows.
- [Research Overview](docs/research/README.md) & [Findings](docs/research/findings.md) — H1–H3 experiments, corpus manifests, and ZIP comparison.
- [Glossary](GLOSSARY.md) — canonical domain vocabulary.

## Repository Layout

```text
cmd/gpack.goose          # CLI entrypoint (pack, list, info, verify, read, help, version)
src/gpack/               # Goose library package (format, pack, reader, native CMake ABI)
third_party/zstd-1.5.7/  # Pinned vendored Zstandard 1.5.7 source
tests/                   # Goose ABI, format v1, golden-byte, and end-to-end test suites
scripts/gpack.py         # Provider-neutral format, check, build, and test runner
.github/workflows/ci.yml # Native Linux/macOS/Windows CI matrix
docs/                    # API, CLI, product spec, format v1, architecture, research
```

## License & Third-Party Notices

`gpack` is licensed under the [MIT License](LICENSE).

Static builds embed Zstandard `1.5.7` (`third_party/zstd-1.5.7/`), distributed under its BSD/GPLv2 dual license. Release builds copy `LICENSE` and `COPYING` into `build/THIRD_PARTY_NOTICES/` (see [Release Procedure](docs/release.md)).
