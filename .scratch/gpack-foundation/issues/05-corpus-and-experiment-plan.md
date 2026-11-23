# Select the representative corpus and experiment sequence

Type: grilling
Status: resolved
Blocked by: 01, 02, 03, 04, 09

## Question

Which real or openly redistributable game/runtime asset corpus and access
patterns represent the target workload, and which H1-H3 experiments are
necessary before freezing architecture defaults? Specify corpus composition,
controls, machine/toolchain records, metrics, repeat counts, decision
thresholds, and experiment order. Keep preregistration and result artifacts
separate from implementation tickets.

## Comments

- User selections: gate format/performance choices on pinned Godot 4.7 demo
  projects plus deterministic generated controls; run H2 framing, then H3
  Goose/native boundary, then H1 queue payload cost; collect five measured runs
  and require correctness/determinism as hard gates, adopting added complexity
  only for repeatable material gains.

## Answer

Use three complete pinned Godot 4.7 demos as the real mixed corpus: one each
from 2D, 3D, and audio. Inventory each category, review candidate project and
embedded third-party notices, then select the eligible candidate whose regular
file count is closest to that category's median. Include each selected
project's regular files and retain its notices. Verify each release ZIP using
the published SHA-256 and record source URLs, release identifiers, local and
published hashes, selected project names, included paths, sizes, and per-file
hashes in a corpus manifest. Exclude candidates with unresolved third-party
terms and choose the next closest eligible candidate. Pair this real corpus
with deterministic generated controls for small-file count, large-file size,
and compressibility; keep generated results distinct from real-corpus results.
The bundled WAD remains a single-file correctness fixture, not a multi-asset
corpus unless a documented extraction step is later added.

Run H2 framing, H3 Goose/native boundary, then H1 queue payload cost. Use five
paired measured runs per configuration, report medians and spreads, and record
CPU, OS, compiler, codec version/build options, corpus checksums, and storage
medium. Correctness and byte-for-byte deterministic output are hard gates. A
material gain requires at least a 10% median throughput improvement or 20%
median peak-RSS reduction, with at least four of five paired runs moving in the
same direction. Added complexity must meet a material threshold; H2 chunking
must also keep median archive-size and full-read costs within 5% of the simpler
layout, and H1 staging must keep its other primary metric within a 5% regression.
For H3, the mixed implementation must remain within 10% median throughput of
the C reference on large assets and preserve Goose-side format policy and
malformed-input rejection. Smaller or inconsistent changes are inconclusive.

Updated H1-H3 preregistrations with this corpus method, measurement procedure,
and decision rule. The actual project inventory and benchmark runs remain
follow-up tasks; no corpus was downloaded or experiment run in this decision.
