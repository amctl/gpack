# Larger real-project workload

Status: acquired, source archive verified, notice-scanned, and benchmarked in
the supplementary Linux runtime run. The project remains outside the repo.

## Recommendation

Add the pinned Godot 4.7 `3d/material_testers` project as a larger real-project
workload alongside the existing three-demo corpus. The official release ZIP
is 104,897,151 bytes and its SHA-256 matches the release asset's published
`f84524261ec5c1012af6e66f5304861f4f1afa0eef78daf71f2791897397ad87`.
`unzip -t` passed. The extracted workload has 109 regular files totaling
133,365,708 bytes (about 127.1 MiB), versus 63 files and 1,197,336 bytes in
the existing `godot-real` workload. It is about 111 times larger by source
bytes. Its largest file is `backgrounds/park.hdr` at 29,029,087 bytes, below
the default 32 MiB per-asset limit. Per-file hashes are recorded in the
[material-testers manifest](experiments/godot-4.7-corpus/material-testers-manifest.json).

The supplementary five-pair Linux run measured 1,046.8 MiB/s median Goose
throughput versus 1,103.5 MiB/s for C (paired median ratio 0.970), within the
existing 10% gate on this corpus/host. Goose median process peak RSS was
106,684 KiB versus 170,544 KiB for C. This remains a single, rendering-focused
project and one warm-cache Linux host, so it supports workload coverage but
does not justify universal performance or memory claims. Full observations
are in [the expanded results](experiments/v1-runtime-throughput/results-larger-corpus.md)
and [raw data](experiments/v1-runtime-throughput/results-larger-corpus.json).

The project README describes a collection of sphere-like objects with complex
materials for showcasing Godot rendering capabilities. The official asset
listing identifies the demo as MIT licensed. The pinned repository README
states that its demos are distributed under MIT, and the archive contains the
MIT `LICENSE.md`; it was retained in the corpus. A scan found no other
license/notice files in this project archive. The inventory records bundled
notices, not independent provenance for every artwork asset; the corpus is a
local research input and its binaries are not committed.

## Reproduction source

- Repository: [godotengine/godot-demo-projects](https://github.com/godotengine/godot-demo-projects)
- Release/tag: [`4.7-6ad6167`](https://github.com/godotengine/godot-demo-projects/releases/tag/4.7-6ad6167)
- Commit: [`6ad6167`](https://github.com/godotengine/godot-demo-projects/commit/6ad6167)
- Source snapshot URL:
  <https://codeload.github.com/godotengine/godot-demo-projects/zip/refs/tags/4.7-6ad6167>
- Official project ZIP URL:
  <https://github.com/godotengine/godot-demo-projects/releases/download/4.7-6ad6167/3d_material_testers.zip>
- Official ZIP SHA-256:
  `f84524261ec5c1012af6e66f5304861f4f1afa0eef78daf71f2791897397ad87`
- Workload subdirectory: `3d/material_testers`
- Project README at the pinned commit:
  [raw source](https://raw.githubusercontent.com/godotengine/godot-demo-projects/6ad6167/3d/material_testers/README.md)
- Repository license at the pinned commit:
  [LICENSE.md](https://raw.githubusercontent.com/godotengine/godot-demo-projects/6ad6167/LICENSE.md)
- Repository statement that the demos are MIT licensed:
  [README.md at the pinned commit](https://raw.githubusercontent.com/godotengine/godot-demo-projects/6ad6167/README.md)
- Official asset listing:
  [Material Testers Demo](https://godotengine.org/asset-library/asset/2742)

To reproduce, download the official ZIP, verify its published SHA-256, extract
it, and use the `material_testers/` directory as the input root. The checked-in
manifest records path, size, and SHA-256 for every extracted regular file,
including the MIT notice. Do not commit the corpus binaries.

## Comparison with current workloads

| Workload | Files | Source bytes | Evidence |
|---|---:|---:|---|
| Existing Godot real workload | 63 | 1,197,336 | [v1 runtime results](experiments/v1-runtime-throughput/results.md) |
| `3d/material_testers` | 109 | 133,365,708 | [Extracted project manifest](experiments/godot-4.7-corpus/material-testers-manifest.json) |

This is one rendering-focused demo and does not represent a user's full
shipped game. Report it as an additional real-project workload, not as a
universal workload or proof of general memory/performance behavior.

## Primary sources

- Godot demo repository README at commit `6ad6167` (project purpose and MIT
  statement), linked above.
- Godot demo repository `LICENSE.md` at commit `6ad6167`, linked above.
- Godot's pinned [`3d/material_testers/README.md`](https://raw.githubusercontent.com/godotengine/godot-demo-projects/6ad6167/3d/material_testers/README.md).
- Godot's [4.7 demo release](https://github.com/godotengine/godot-demo-projects/releases/tag/4.7-6ad6167).
- Godot Asset Library, [Material Testers Demo](https://godotengine.org/asset-library/asset/2742), which lists MIT.
