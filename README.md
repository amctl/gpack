# gpack

gpack is a Goose-oriented asset archive project. The v1 contract, pinned native
build foundation, Goose-owned format primitives, compressed/raw pack and read
path, `list`/`verify`, input safety, configurable limits, and atomic output are
implemented. Runtime performance is accepted on the measured Linux build;
cross-platform release validation remains.
H1, H2, and both H3 experiments are complete.
The H3 runtime prototype missed its throughput target. Issue 22 then measured
the product v1 reader and met the 10% throughput gate on Linux; cross-platform
release validation remains open in issue 23.

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
