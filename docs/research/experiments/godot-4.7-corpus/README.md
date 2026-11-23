# Godot 4.7 benchmark corpus

Status: acquired and inventoried; no benchmark has run. Corpus binaries remain
outside the repository.

## Pinned source and selection

Use the official [Godot demo projects 4.7 release](https://github.com/godotengine/godot-demo-projects/releases/tag/4.7-6ad6167),
tag `4.7-6ad6167` at commit `6ad6167`. The repository describes the demos as
MIT licensed. The release metadata lists individually downloadable project
ZIPs and SHA-256 digests. The source snapshot used to calculate category
medians was downloaded from
[`codeload.github.com/.../4.7-6ad6167`](https://codeload.github.com/godotengine/godot-demo-projects/zip/refs/tags/4.7-6ad6167);
its local SHA-256 was
`1defa1dc1edee7463c558e497b71ac039d566a50473425d63e83bd7391345512` (the
snapshot URL does not publish a separate checksum).

Inventory method: recursively count regular files beneath every `project.godot`
directory in the 2D, 3D, and audio source trees. Include hidden regular files
such as `screenshots/.gdignore`; do not follow symlinks. Select the project
nearest the category median among candidates with clear, reviewed notices. For
ties, prefer lower third-party attribution burden, then the lexicographically
first project path. The full candidate path/count inventory and per-file
manifest are in [`manifest.json`](manifest.json).

| Category | Projects inventoried | Median source-tree files | Selected project | Source-tree files | Released ZIP files | Unpacked bytes |
|---|---:|---:|---|---:|---:|---:|
| 2D | 27 | 22 | `2d/kinematic_character` | 22 | 23 | 58,933 |
| 3D | 32 | 26.5 | `3d/lights_and_shadows` | 26 | 27 | 363,791 |
| Audio | 9 | 12 | `audio/mic_record` | 12 | 13 | 774,612 |

The selected release ZIPs add a common `LICENSE.md`, so their actual packaged
file counts are one higher than the source-tree counts used for median
selection. Every file in the selected project ZIPs is included, including
README files, import metadata, screenshots, `.gdignore`, and license notices.

## Notice review

- `2d/kinematic_character`: the project README identifies the demo but lists no
  separate asset notices. The distributed project ZIP includes the repository's
  MIT `LICENSE.md`; no additional license marker appeared in the project tree.
- `3d/lights_and_shadows`: the ZIP includes the same MIT `LICENSE.md` and
  `checker.LICENSE.md`, which identifies `checker.png` as Kenney artwork under
  CC0 1.0. Keep both notices in the benchmark input. The project README lists
  no other asset credit.
- `audio/mic_record`: the ZIP includes the MIT `LICENSE.md`. Its README lists no
  separate asset notice; `Intro.ogg` has no embedded artist/title/license tags,
  and no additional project license marker was found. The repository's MIT
  statement and included `LICENSE.md` cover the selected distribution.

Two median ties were reviewed. In 2D, `kinematic_character` and `particles`
both have 22 source-tree files and no separate third-party notice; the path
tie-break selects `kinematic_character`. In 3D, `global_illumination` (26 files)
documents a CC BY 4.0 Sauerbraten-derived model. `lights_and_shadows` (26 files)
includes one CC0 checker notice, while `soft_body_physics` (27 files) includes
a CC0 checker plus three Poly Haven CC0 textures. `lights_and_shadows` has the
lowest third-party asset and notice burden. In audio, `mic_record` and
`spectrum` both have 12 files and MIT project licenses; `spectrum` also has a
named track in its audio metadata. With no additional restrictive terms found,
the lexicographic tie-break selects `mic_record`.

## Acquisition and verification

The exact per-project source URLs, published SHA-256 values, matching local
SHA-256 values, unpacked sizes, extension counts, and path-level hashes are in
[`manifest.json`](manifest.json). Each selected project archive was downloaded
from its release URL, passed `unzip -t`, and matched the release API's published
SHA-256. For example:

```sh
curl -L 'https://github.com/godotengine/godot-demo-projects/releases/download/4.7-6ad6167/2d_kinematic_character.zip' -o 2d_kinematic_character.zip
echo '898a8d4b89d5fcce4fbe6cccbf1b7c89fc34d0d0ca422a217abc3d6ffb97aa05  2d_kinematic_character.zip' | sha256sum -c
```

Repeat with the URLs and hashes in the manifest for the 3D and audio archives.
Unpack each ZIP, retain the included notices, and use the paths and SHA-256
values in the manifest to verify the extracted corpus. Do not commit the ZIPs
or extracted corpus.

## Larger real-project workload

The supplementary runtime benchmark also uses the pinned release asset
[`3d_material_testers.zip`](https://github.com/godotengine/godot-demo-projects/releases/download/4.7-6ad6167/3d_material_testers.zip),
published SHA-256
`f84524261ec5c1012af6e66f5304861f4f1afa0eef78daf71f2791897397ad87`.
The verified local extraction has 109 regular files totaling 133,365,708
bytes; the largest file is 29,029,087 bytes. The release archive passed
`unzip -t`. Its included MIT `LICENSE.md` was retained, and no other
license/notice files were present. The file-level size/hash inventory is
[`material-testers-manifest.json`](material-testers-manifest.json); binaries
remain outside the repository. Runtime measurements are in the
[expanded benchmark results](../v1-runtime-throughput/results-larger-corpus.md).

## Sources

- [Godot demo repository and MIT statement](https://github.com/godotengine/godot-demo-projects)
- [Pinned demo MIT license](https://github.com/godotengine/godot-demo-projects/blob/6ad6167/LICENSE.md)
- [Pinned 4.7 release and release assets](https://github.com/godotengine/godot-demo-projects/releases/tag/4.7-6ad6167)
- [Kinematic Character 2D demo](https://store.godotengine.org/asset/godot-foundation/kinematic-character-2d-demo/)
- [Lights and Shadows 3D demo](https://store.godotengine.org/asset/godot-foundation/lights-and-shadows-3d-demo/)
- [Audio Mic Record source project](https://github.com/godotengine/godot-demo-projects/tree/6ad6167/audio/mic_record)
- [Kenney prototype textures and CC0 license](https://kenney.nl/assets/prototype-textures)
- [Pinned checker texture notice](https://github.com/godotengine/godot-demo-projects/blob/6ad6167/3d/lights_and_shadows/checker.LICENSE.md)
- [Poly Haven Fabric Pattern 07 (CC0)](https://polyhaven.com/a/fabric_pattern_07)
- [Poly Haven asset license](https://polyhaven.com/license)
- [Godot's guidance to retain asset notices](https://docs.godotengine.org/en/4.7/about/complying_with_licenses.html)
