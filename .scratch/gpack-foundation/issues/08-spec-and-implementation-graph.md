# Synthesize the build-ready spec and implementation graph

Type: task
Status: resolved
Blocked by: 01, 02, 03, 04, 05, 06, 07

## Question

Turn the resolved decisions and evidence into one coherent product spec,
architecture map, canonical file/folder tree, risk register, and blocker-linked
tracer-bullet implementation tickets. Audit every project document for
contradictions and stale references. Recommend which research/bootstrap files
to retain, consolidate, or remove, then leave the repository at the agreed
implementation-ready start state without adding implementation code.

## Answer

The canonical v1 decisions are recorded in:

- [`docs/product/spec.md`](../../../docs/product/spec.md) — product scope,
  commands, runtime API, integrity, compression, limits, and platform contract.
- [`docs/format/v1.md`](../../../docs/format/v1.md) — normative v1 wire
  format, bounds, checksums, path bytes, and decoder requirements.
- [`docs/product/architecture.md`](../../../docs/product/architecture.md) —
  Goose/native responsibilities, data flow, canonical tree, and propagation
  rules.
- [`docs/product/risks.md`](../../../docs/product/risks.md) — runtime
  performance, ZIP justification, cross-platform determinism, memory, path,
  source mutation, ABI, and checksum risks with gates.

Issues [17–23](../map.md#implementation-tickets) form the implementation graph.
Each has explicit blockers and acceptance criteria. The sequence starts with
the native build foundation, then format primitives and a raw pack/read slice,
adds Zstandard/list/verify and input hardening, resolves the runtime throughput
gate, and validates the release matrix. No product source code was added.

### Documentation disposition

- Retain experiment protocols, full JSON observations, result reports, the
  corpus inventory/notices, primary-source survey, focused evidence notes, and
  the chronological research log. They preserve evidence that the spec relies
  on.
- Retain `docs/product/proposal.md` as historical context, clearly marked as
  superseded. The accepted spec, format, architecture, and risk register are
  canonical.
- Remove the initial HTML bootstrap handout and the superseded documentation
  architecture plan/spec. Their navigation and document-truth guidance now
  live in README, AGENTS, the research index, and this implementation graph.
- Keep `.scratch/gpack-foundation/` as the issue tracker. Do not move planning
  tickets into the research experiment tree.

The custom format remains a user-selected product decision, not a measured win
over restricted ZIP. Runtime performance is also not accepted: the Goose H3
prototype missed the 10% C gap. These are explicit gates in the risk register
and implementation tickets, rather than hidden assumptions.
