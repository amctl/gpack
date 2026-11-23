# GPack foundation and build plan

## Destination

A build-ready product spec and blocker-linked implementation plan for a Goose
game/runtime asset archive, with a crisp v1 contract, validated architecture,
experiment results where needed, and a lean, internally consistent repository
that is ready for implementation. Issue 08 completes this documentation goal;
implementation proceeds through issues 17–23.

## Notes

- The working product target is an asset archive for game/runtime use with
  random asset access.
- Use the Wayfinder, research, domain-modeling, and experiment protocols
  documented in this repository. Research claims must link to primary sources.
- Preserve concise evidence, decisions, and experiment protocols/results;
  remove redundant bootstrap or process artifacts after their useful content
  has been incorporated into canonical project docs.
- At planning time, the checkout had no gpack implementation or product
  baseline. Issues 17–22 have since implemented v1 and met the product runtime
  throughput gate on Linux; issue 23 retains cross-platform validation.
- Keep decisions and implementation tasks distinct. The spec and task graph are
  ready; implementation must follow the blocker-linked tickets below.

## Decisions so far

- [Establish the v1 user workflow and product contract](issues/01-product-contract.md): build-time CLI creates a new versioned archive; runtime API reads individual assets; v1 targets Goose desktop platforms, regular files, and safe normalized paths.
- [Choose the archive access and framing model](issues/02-archive-format-and-access-model.md): random access alone does not justify a custom format; the user selected the new versioned format for v1, with its comparative benefit over restricted ZIP retained as an explicit risk.
- [Verify the Goose implementation boundary](issues/03-goose-implementation-boundary.md): Goose v2026.4 makes a native streaming/codec boundary plausible for bounded-memory large-asset handling, but the need and performance must be experimentally validated.
- [Define archive safety and reproducibility guarantees](issues/04-security-and-determinism-contract.md): v1 omits host timestamps/permissions, rejects duplicate normalized paths and non-regular inputs, fails on detected source mutation, promises reproducible bytes for pinned inputs/options/codec, and detects accidental corruption without an authenticity claim.
- [Define runtime lookup and archive update behavior](issues/09-runtime-lookup-contract.md): normalized-path lookup returns complete assets from a separately distributable, read-only archive; concurrent independent reads are required; replacement is whole-archive and external to gpack.
- [Research codec options for reproducible desktop builds](issues/10-codec-dependency-research.md): Zstandard and LZ4 both support independent whole-asset frames and optional corruption checks; issue 06 selects pinned Zstandard 1.5.7 at level 3, with cross-platform output identity still to validate.
- [Find a redistributable game-asset corpus for experiments](issues/11-corpus-source-research.md): pinned Godot demos are the leading mixed corpus candidate; pair them with generated controls, and review notices before acquisition.
- [Select the representative corpus and experiment sequence](issues/05-corpus-and-experiment-plan.md): use one notice-cleared Godot 4.7 demo per 2D/3D/audio group, selected near each group's median file count; run H2 → H3 pack-side → H1, then revisit runtime lookup.
- [Inventory the pinned Godot benchmark corpus](issues/12-inventory-benchmark-corpus.md): verified release `4.7-6ad6167` and selected `2d/kinematic_character`, `3d/lights_and_shadows`, and `audio/mic_record`; candidate counts, notice review, archive checksums, and per-file hashes are in the corpus manifest.
- [Run H2 framing and processing-granularity experiment](issues/13-run-archive-design-experiments.md): chunking met material-gain/cost rules on large high-entropy and mixed controls, but repetitive large assets compressed much worse and the real corpus showed no material advantage; results leave the default open.
- [Run H3 Goose/native boundary experiment](issues/14-run-h3-native-boundary-experiment.md): the pack-side streaming boundary met gain/cost rules and matched the C reference; issue 16 measured indexed concurrent reads, passed correctness, and missed the Goose throughput gate.
- [Run H1 queue payload cost experiment](issues/15-run-h1-queue-payload-experiment.md): metadata staging met gain/cost rules for large high-entropy chunks at higher worker counts, but not on the real corpus or compressible control; staging is a selective option, not a default.
- [Measure native-backed indexed runtime lookup](issues/16-measure-native-runtime-lookup.md): Goose/native and C readers passed correctness and malformed-input gates, but Goose throughput missed the 10% target by 27.4% on the real corpus and 12.1% on mixed; queue/allocation overhead and a practical memory budget remain follow-up work.
- [Set the v1 feature and dependency boundary](issues/06-v1-feature-and-dependency-boundary.md): v1 uses pack/list/verify plus complete path reads, pinned Zstandard 1.5.7 with raw fallback and CRC32 integrity, no deduplication, and a configurable 32 MiB asset limit with four concurrent reads by default; larger surfaces and capabilities are deferred.
- [Design the repository and build foundation](issues/07-repository-and-build-foundation.md): one Goose package owns the format and runtime policy; a thin CLI imports it, while a shared ABI header keeps native I/O/Zstandard declarations aligned. Pin Goose/Zstandard, build natively on Linux/GCC, macOS/Apple Clang, and Windows/MSVC, run correctness gates in CI, and keep benchmarks manual.
- [Synthesize the build-ready spec and implementation graph](issues/08-spec-and-implementation-graph.md): accepted product spec, normative format, architecture map, risk register, and tickets 17–23 are ready; no product implementation code was added.
- [Bootstrap the Goose/native build foundation](issues/17-build-foundation.md): Goose v2026.4 package and CLI skeleton, pinned static Zstandard 1.5.7, ABI probe, provider-neutral scripts, and a native three-platform CI matrix are in place; local format/type checks and C compilation pass, while full native linkage and non-Linux matrix results await CI.
- [Implement v1 format primitives and validation](issues/18-format-v1-primitives.md): Goose now encodes and validates v1 headers/indexes, CRC32, canonical paths, and payload ranges; exact checked-in fixtures and malformed-input cases pass in the format test.
- [Deliver the raw pack/read vertical slice](issues/19-raw-pack-read-slice.md): deterministic raw directory packing, mutation checks, complete path reads, and four-worker positional reads are implemented and pass Linux end-to-end validation.
- [Add Zstandard, raw fallback, listing, and verification](issues/20-zstd-list-verify.md): streaming Zstandard 1.5.7 level 3 with frame checksums, per-asset CRC32, raw fallback, strict one-frame reads, and `list`/`verify` pass local Goose and Linux end-to-end checks; pinned static CMake linkage and platform CI remain for issue 23.
- [Harden input scanning, limits, and atomic output](issues/21-input-safety-and-atomic-output.md): unsafe/non-regular inputs are rejected, runtime read limits are configurable, and sibling-temp flush/replace preserves an existing destination after detected source mutation; Linux validation passes, with cross-platform execution assigned to issue 23.
- [Meet the runtime throughput acceptance gate](issues/22-runtime-throughput-acceptance.md): the product v1 Goose reader met the 10% median throughput gate against a C reference on five paired Linux runs for Godot-real and mixed workloads, with correctness, malformed-input, latency, RSS, and four-reader/32 MiB default measurements recorded in the benchmark report.
- [Validate cross-platform archives and release artifacts](issues/23-platform-release-gate.md): the production CMake path, golden archive, Unicode/case lookup, static Zstandard linkage, and notices pass on Linux; native macOS/Windows CI and cross-platform golden-byte matches remain to be verified.

## Implementation tickets

1. [20 — Add Zstandard, raw fallback, list, and verify](issues/20-zstd-list-verify.md)
2. [21 — Harden input scanning, limits, and atomic output](issues/21-input-safety-and-atomic-output.md)
3. [23 — Validate cross-platform archives and release artifacts](issues/23-platform-release-gate.md)

## Not yet specified

- Validate the runtime implementation and 32 MiB/four-reader defaults on the
  remaining supported platforms; implementation gate is issue 23.

## Wayfinder scope limits

- Issue 08 prepares the implementation start state but does not implement
  gpack or publish a release.
- Claiming the custom format beats ZIP without a comparative measurement.
- Modifying the ignored `goose-bin/` research input.
- Supporting mobile/consoles or legacy archive import/export.
