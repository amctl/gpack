# Find a redistributable game-asset corpus for experiments

Type: research
Status: resolved

## Question

Using authoritative project and license sources, identify one or more real
game/runtime asset corpora that can be lawfully downloaded and redistributed
for gpack benchmarking. Compare file-type/size diversity, total scale, license
clarity, stable versioning/checksums, and fit with the selected desktop/runtime
workload. Do not download or commit corpus binaries; give exact source and
license links and a reproducible acquisition recommendation.

## Answer

Use pinned Godot demo projects as the leading mixed real-world candidate,
paired with deterministic generated files for controlled size/compressibility
sweeps. The Godot 4.7 release publishes SHA-256 values and the repository says
its demos are MIT licensed, but each selected project still needs third-party
notice review and a local unpacked-tree inventory. Kenney RPG Base is an
optional CC0 small-asset corpus. The bundled Freedoom WAD is one gpack input as
is; its lumps only become a many-file fixture through a documented extraction
step. No corpus was downloaded. See
[`docs/research/wayfinder-corpus-sources.md`](../../../docs/research/wayfinder-corpus-sources.md).
