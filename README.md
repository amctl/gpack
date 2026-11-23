# gpack

gpack is a Goose-oriented asset archive project.

## Status

- **Completed:** v1 packing, reading, `list`/`verify`, input safety, and atomic
  output are implemented. The [Linux build and correctness run](.scratch/gpack-foundation/issues/23-platform-release-gate.md)
  passed, and the [runtime throughput gate](docs/research/experiments/v1-runtime-throughput/results.md)
  passed on the measured Linux host. A supplementary run added a 127 MiB,
  109-file [Godot Material Testers project](docs/research/experiments/v1-runtime-throughput/results-larger-corpus.md):
  median throughput remained within 10% of C and Goose used less peak RSS on
  that host. The completed [restricted ZIP comparison](docs/research/experiments/restricted-zip-comparison/results.md)
  found a small raw-container size advantage for GPack and workload-dependent
  tradeoffs between GPack Zstandard/raw and ZIP DEFLATE. No general winner is
  established. These results cover specific workloads and are not general
  performance or memory guarantees. H1, H2, both H3 experiments, the v1
  throughput gate, and the ZIP comparison are complete; see the
  [research findings](docs/research/findings.md).
- **Open release blockers:** native macOS and Windows CI, plus cross-platform
  golden archive byte identity, remain unverified in [issue 23](.scratch/gpack-foundation/issues/23-platform-release-gate.md).
- **Next decision:** retain the selected v1 format for the measured workflow,
  with the ZIP tradeoffs recorded in [issue 24](.scratch/gpack-foundation/issues/24-restricted-zip-comparison.md).
  Revisit if representative target projects or interoperability needs change
  the balance. Complete the deferred native macOS/Windows checks before release.

## Project map

- [Glossary](GLOSSARY.md) — canonical project and domain terms.
- [V1 product specification](docs/product/spec.md) — accepted product
  contract and limits.
- [V1 architecture](docs/product/architecture.md) — module boundaries and
  implementation flow.
- [V1 format](docs/format/v1.md) — normative archive layout.
- [Risk register](docs/product/risks.md) — remaining acceptance gates.
- [Release procedure](docs/release.md) — tag and platform-validation steps.
- [Research overview](docs/research/README.md) — where to find evidence,
  findings, source reviews, and experiment status.
- [Current findings](docs/research/findings.md) — the current synthesis and
  unresolved decisions.
- [Implementation graph](.scratch/gpack-foundation/map.md) — resolved
  decisions and blocker-linked implementation tickets.
- [Planning conventions](docs/agents/issue-tracker.md) — issue and research
  workflow.
- [Historical proposal](docs/product/proposal.md) — initial recommendations,
  superseded by the accepted v1 specification.

Planning issues in `.scratch/` are separate from research protocols and results
under `docs/research/experiments/`. The ignored `goose-bin/` directory is a
local Goose toolchain and research input, not gpack source code.
