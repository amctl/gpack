# Research log

## 2026-11-24 — Restricted ZIP comparison

- Implemented a research-only Goose ZIP writer/reader for classic single-disk
  ZIP with STORED and DEFLATE, plus a raw GPack packer to isolate container
  overhead. ZIP remains outside the product package and CLI.
- Correctness, malformed-input, deterministic-output, four-reader, and
  interoperability checks passed before paired measurements on the small real,
  deterministic mixed, and larger Material Testers workloads. Results show a
  small raw-container size advantage and codec tradeoffs that vary by corpus;
  they do not establish a general winner. See the
  [report](experiments/restricted-zip-comparison/results.md) and
  [raw observations](experiments/restricted-zip-comparison/results.json).

## 2026-11-24 — Larger real-project workload

- Acquired the official Godot 4.7 `3d_material_testers.zip`, verified its
  published SHA-256 and ZIP integrity, retained its MIT notice, and recorded a
  SHA-256 for every extracted file. The 109-file input totals 133,365,708
  bytes; its largest asset is below the default 32 MiB limit.
- Ran five paired Goose/C reads with the production CMake-linked build. On this
  Linux host, the 127 MiB project measured a 0.970 median paired throughput
  ratio; Goose median peak RSS was 106,684 KiB. Results and limits are in the
  [expanded report](experiments/v1-runtime-throughput/results-larger-corpus.md).
- The small real workload rerun was noisy and had a 0.808 median paired ratio.
  Performance and memory claims remain scoped to named workloads and host.

## 2026-11-24 — Restricted ZIP capability review

- Compared PKWARE ZIP/ZIP64 capabilities with the accepted GPack v1 runtime
  and build contract. ZIP can support streaming construction and central-
  directory indexed complete-member lookup; path safety, bounded parsing,
  reproducibility, memory limits, and concurrent reads remain application
  policy. No ZIP implementation or performance result was measured.
- Proposed a restricted single-volume UTF-8 profile and separated STORED vs
  GPack raw (container-focused) from DEFLATE vs GPack Zstandard/raw (full
  profile) comparisons. The detailed source review and preregistered protocol
  are [here](zip-profile-capabilities.md) and
  [here](experiments/restricted-zip-comparison/protocol.md).
- Added issue 24 to implement and measure the Goose comparison; issue 23's
  deferred macOS/Windows validation remains open.

## 2026-11-22 — Bootstrap and initial prior-art pass

- Applied the autoresearch workflow requested by the user. This is a research
  bootstrap; no implementation or experiment has been run.
- Repository inspection: the [product proposal](../product/proposal.md) is
  detailed; no packer source,
  build configuration, or existing research state is present. `goose-bin/`
  contains a Goose toolchain bundle, docs, standard library, examples, and game
  packages/assets.
- Examined local Goose examples: `12_huffman.goose` (codec-shaped algorithm),
  `23_mandelbrot_threads.goose` (typed queue workers with out-of-order result
  collection), `25_serialize.goose` (safe serialization and explicit external
  binary parsing), `31_mini_doom.goose` (real WAD parsing), and
  `32_pool_worker_snapshots.goose` (workers receive copied state snapshots).
- Examined `stdlib/os.goose`: `read_file` materializes the entire file;
  directory listing returns newline-separated names; atomic whole-file write
  exists; no persistent file handles, positional reads, or streaming writes are
  exposed in this API.
- Primary-source prior art reviewed: libarchive's stream-first design and
  format tradeoffs; ZIP's local headers plus end directory; Zstandard seekable
  frames and per-thread contexts; Quake II PAK writer; Goose specification and
  implementation notes. See [`prior-art/survey.md`](prior-art/survey.md).
- Initial synthesis: the proposed ordered writer is a useful determinism
  pattern, but sending large chunk payloads through Goose typed queues adds a
  copy and bounded message count does not bound bytes. Start with a small
  correctness-first format and measure the queue/copy boundary before
  committing to chunk size, deduplication, or compression defaults.
- Continuity: the session had no `/loop` or cron interface. This limitation was
  initially recorded in the state file and is retained here as historical
  session context; it does not describe current research progress.

## 2026-11-23 — Documentation organization

- Grouped the product proposal under `docs/product/` and research notes,
  preregistered protocols, state, and the HTML handout under `docs/research/`.
- Added root and research navigation pages and repaired paths after the moves.
- No implementation or experiment was added. H1, H2, and H3 remain
  preregistered and unrun; choosing an experiment order and representative
  corpus is the next research step.

## 2026-11-23 — Wayfinding and focused evidence

- Started the `.scratch/gpack-foundation/` Wayfinder map toward a build-ready
  spec and blocker-linked implementation plan. The user selected a build-time
  archive CLI plus runtime individual-asset lookup, Goose desktop platforms,
  a new versioned format without legacy import/export, regular-file inputs,
  safe normalized paths, separately distributable archives, deterministic
  bytes for the same inputs/options/pinned codec build, and accidental
  corruption detection without authenticity/signature claims.
- Primary-source archive comparison found that ZIP already supports streaming
  construction plus indexed lookup; random access alone does not justify a
  custom format. See [`wayfinder-format-access.md`](wayfinder-format-access.md).
- Checked Goose v2026.4 against its bundled docs and current official docs.
  Whole-file I/O and copied, message-count-bounded queues make a native
  streaming boundary plausible for bounded-memory large files, but no
  performance result exists. See
  [`wayfinder-goose-boundary.md`](wayfinder-goose-boundary.md).
- Profiled the bundled Freedoom WAD directory as a local corpus candidate:
  1,220 internal lumps, mostly small, none above 1 MiB. The WAD is one 4.8 MB
  gpack input as-is; the lumps are not separate files unless explicitly
  extracted. See
  [`wayfinder-corpus-inventory.md`](wayfinder-corpus-inventory.md).
- Corrected the corpus interpretation after reviewing the Goose sample: its
  WAD lumps are not many-small-file inputs unless materialized into a derived
  directory. Primary-source research identified pinned Godot demos plus
  generated controls as a better initial mixed corpus candidate, pending local
  acquisition, notice review, and inventory. See
  [`wayfinder-corpus-sources.md`](wayfinder-corpus-sources.md).
- Compared Zstandard and LZ4 from official specifications and build/license
  sources. Both support per-asset frames and optional accidental-corruption
  checks; benchmark results must decide whether to include one. See
  [`wayfinder-codec-options.md`](wayfinder-codec-options.md).
- No gpack implementation or H1-H3 benchmark experiment has run. The user
  contract and experiment order are selected; exact demo-project membership,
  notice review, codec/build and checksum coverage, feature boundary, the
  evidence required to justify the new format, and repository architecture
  remain open in the map.

- The runtime contract is now path lookup of complete assets, with concurrent
  independent reads from a read-only archive; the application replaces the
  whole archive outside gpack. H2 was revised to remove partial-range latency
  and compare whole-asset frames with chunked build/full-read tradeoffs. The
  user selected pinned Godot 4.7 demo projects plus generated controls and the
  H2 → H3 → H1 sequence, with five measured runs and correctness/determinism as
  hard gates. These protocols remain unrun.
- Resolved the corpus and experiment-plan decision: choose one notice-cleared
  complete demo per 2D, 3D, and audio category, nearest each category's median
  regular-file count; keep deterministic generated controls separate. Added
  paired-run and material-gain thresholds to H1-H3. Corpus acquisition and
  inventory, then H2 → H3 → H1 as separate ordered tasks, are tracked as
  Wayfinder issues 12–15; no benchmark result is claimed.
- Resolved corpus inventory issue 12. The pinned release contains 27 2D, 32 3D,
  and 9 audio projects; selected median-count demos are `2d/kinematic_character`,
  `3d/lights_and_shadows`, and `audio/mic_record`. All three release ZIPs matched
  their published SHA-256 values. Candidate file counts and type/size
  distributions, selected file hashes, and notice review are in
  [`experiments/godot-4.7-corpus/`](experiments/godot-4.7-corpus/). No benchmark
  experiment has run.
- Completed H2 with five paired runs across five workload classes and layouts.
  Correctness, determinism, and malformed-input gates passed. Chunking met the
  material-gain/cost rule on large high-entropy and mixed controls, while
  repetitive large inputs suffered major compression loss; the small real
  corpus did not distinguish framing choices. The full default question remains
  open. See [`experiments/h2-frame-granularity/results.md`](experiments/h2-frame-granularity/results.md).

- Completed the pack-side H3 comparison with five paired runs for Goose
  whole-file processing, Goose-owned envelope logic over a C streaming backend,
  and a C reference. The native path reduced median RSS by 92.2–95.6% versus
  Goose whole-file processing on large controls, raised median throughput by
  117–137%, and stayed within 10% of C throughput. Correctness, deterministic
  output, short-I/O, injected write-failure cleanup, and malformed-count gates
  passed. The sequential prototype did not test indexed positional reads or
  concurrent runtime lookup; issue 16 tracks that follow-up after H1. See
  [`experiments/h3-native-streaming-boundary/results.md`](experiments/h3-native-streaming-boundary/results.md).

- Completed H1 with 720 independently verified archives across four workloads,
  four chunk sizes, worker counts 1/2/4/16, and five paired runs. Metadata
  staging met the decision rule in five large high-entropy configurations,
  including every tested chunk size at 16 workers; no configuration qualified
  on the real Godot corpus or large compressible controls. Four many-small
  configurations crossed the numerical threshold, but do not establish the
  large-payload queue-copy mechanism. Staging remains a selective option. Issue
  16 is now unblocked to measure indexed runtime lookup. See
  [`experiments/h1-queue-payload-cost/results.md`](experiments/h1-queue-payload-cost/results.md).

- Completed issue 16 with five paired runs per workload for indexed H3 runtime
  lookup. Goose/native and C reference readers passed source-byte and malformed
  input checks. Goose missed the maximum 10% throughput gap (27.4% below C on
  Godot real, 12.1% below on mixed); median RSS was nearly equal. The C ABI is
  functionally viable, but queue/allocation overhead and a practical memory
  budget remain open before a runtime design decision. See
  [`experiments/h3-runtime-lookup/results.md`](experiments/h3-runtime-lookup/results.md).
