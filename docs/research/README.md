# Research

This directory records gpack's evidence and remaining validation work. The v1
spec and implementation graph are ready. Issues 17–22 now provide a product
implementation and a Linux product v1 runtime performance baseline. The H3
runtime prototype missed its target; the product-shaped issue 22 benchmark
met the throughput gate on this host. Cross-platform release validation is
still open. Protocols describe methods and result artifacts record measurements.

## Where things live

- [`findings.md`](findings.md) — current synthesis, constraints, and open
  questions. Use this for the latest evidence-based understanding.
- [`../product/spec.md`](../product/spec.md),
  [`../product/architecture.md`](../product/architecture.md), and
  [`../product/risks.md`](../product/risks.md) — accepted v1 contract,
  architecture, and remaining acceptance gates.
- [`../format/v1.md`](../format/v1.md) — normative archive format.
- [`research-log.md`](research-log.md) — chronological record of research
  activity. Historical entries describe what was known at the time they were
  written.
- [`state.yaml`](state.yaml) — machine-readable project question, status,
  current understanding, experiment queue, and next action.
- [`prior-art/survey.md`](prior-art/survey.md) — source-grounded survey of
  relevant formats, libraries, and Goose capabilities.
- [`prior-art/design-review.md`](prior-art/design-review.md) — detailed review
  of the product proposal against prior designs, Goose constraints, and
  operational risks.
- [`wayfinder-format-access.md`](wayfinder-format-access.md) and
  [`wayfinder-goose-boundary.md`](wayfinder-goose-boundary.md) — focused
  primary-source evidence gathered for current Wayfinder decisions.
- [`wayfinder-codec-options.md`](wayfinder-codec-options.md) and
  [`wayfinder-corpus-sources.md`](wayfinder-corpus-sources.md) — primary-source
  research on codec candidates and redistributable benchmark corpora.
- [`wayfinder-corpus-inventory.md`](wayfinder-corpus-inventory.md) — read-only
  inventory of a bundled WAD fixture and its limits for performance studies.
- [`experiments/`](experiments/) — preregistered protocols and result
  artifacts. H1, H2, both H3 experiments, and the product v1 runtime gate are
  complete; see [`v1-runtime-throughput`](experiments/v1-runtime-throughput/results.md).
- [`experiments/godot-4.7-corpus/`](experiments/godot-4.7-corpus/) — selected
  demo corpus, verified release hashes, inventory, notices, and file manifest.
- [`experiments/v1-runtime-throughput/`](experiments/v1-runtime-throughput/) —
  product v1 paired Goose/C benchmark protocol, results, and raw run data.

The initial [`../product/proposal.md`](../product/proposal.md) is retained as
historical context; use the accepted product and format specifications for
current decisions.

## Planning versus research

Local planning tickets and specifications live under `.scratch/<feature>/` as
described in [`../agents/issue-tracker.md`](../agents/issue-tracker.md).
Research protocols and results belong under `docs/research/experiments/`;
they are not implementation tickets.

The ignored root `goose-bin/` directory is the local compiler, documentation,
and sample bundle used as research input. It is not part of the gpack source
tree.
