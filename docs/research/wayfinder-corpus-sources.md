# Candidate game-asset corpora for gpack experiments

Checked 2026-11-23 against official project and license sources. The pinned
Godot source snapshot and three selected release ZIPs were downloaded to
`/tmp` for inventory; no corpus binaries are stored in the repository. The
selected corpus, candidate counts, exact ZIP checksums, notice review, and
per-file hashes are recorded in
[`experiments/godot-4.7-corpus/`](experiments/godot-4.7-corpus/).

## Candidates

| Candidate | License and reproducibility evidence | Fit and limitations |
|---|---|---|
| [Godot demo projects](https://github.com/godotengine/godot-demo-projects) | The project says its demos are MIT licensed. Release `4.7-6ad6167` points to commit `6ad6167` and publishes SHA-256 values for individual demo ZIPs. | The pinned source tree contains 27 2D, 32 3D, and 9 audio projects. The selected regular-file-count medians are 22, 26.5, and 12. See the corpus manifest for complete category counts, selected project inventory, and notice review. |
| [Kenney RPG Base](https://kenney.nl/assets/rpg-base) | Its official asset page states CC0 and lists 230 files; Kenney's support page says assets on its asset pages are CC0 and may be used commercially. The page lists release 1.0 (2014), but no cryptographic download hash was found in the cited page. | Clear, permissive, small 2D asset set, useful as a supplementary many-small-file corpus. Record a locally computed archive hash at acquisition. It does not represent audio or large assets. |
| [Freedoom](https://github.com/freedoom/freedoom) | The project's official manual and `COPYING.adoc` state a permissive modified three-clause BSD license. Pin a release or commit and hash the downloaded package. | Real game content, but the standard distribution is one or a few WAD files, not an ordinary directory of individual assets. The Goose-bundled E1M1 WAD has 1,220 internal lumps; gpack sees one asset unless a separately documented extraction step materializes those lumps as files. Useful for testing a single medium-sized archive asset or a derived small-file fixture, not a substitute for a mixed tree. |
| [Khronos glTF Sample Assets](https://github.com/KhronosGroup/glTF-Sample-Assets) | The repository records licenses per model in `REUSE.toml` and individual READMEs; licenses vary, including CC0, CC-BY, and third-party-specific terms. Pin a commit and select only folders after reviewing each license. | Good optional 3D-only format/access corpus, but not a clean uniform-license corpus as a whole. Avoid treating the repository-wide collection as redistributable under one license. |

Primary evidence: [Godot demo README](https://github.com/godotengine/godot-demo-projects/tree/6ad6167),
[pinned demo license](https://github.com/godotengine/godot-demo-projects/blob/6ad6167/LICENSE.md),
[Godot 4.7 release assets and checksums](https://github.com/godotengine/godot-demo-projects/releases/tag/4.7-6ad6167),
[Kenney support/license guidance](https://kenney.nl/support),
[Kenney RPG Base page](https://kenney.nl/assets/rpg-base),
[Freedoom manual](https://github.com/freedoom/freedoom/blob/master/manual/freedoom-manual-en.adoc),
[Freedoom COPYING](https://github.com/freedoom/freedoom/blob/master/COPYING.adoc),
[glTF sample repository](https://github.com/KhronosGroup/glTF-Sample-Assets), and
[its per-path license manifest](https://github.com/KhronosGroup/glTF-Sample-Assets/blob/main/REUSE.toml).

## Recommendation

Use three layers, each answering a different question:

1. Keep the bundled Freedoom WAD as a tiny correctness fixture. Do not count
   its internal lumps as gpack files unless the experiment explicitly uses a
   reproducible WAD-to-files extraction step.
2. Use the pinned release's `2d/kinematic_character`,
   `3d/lights_and_shadows`, and `audio/mic_record` projects. They are nearest
   their category medians after notice review and tie-breaking. Verify the
   selected project ZIPs using published SHA-256 values, include all regular
   files, and retain every license notice. The exact candidate distribution,
   selected paths, archive hashes, unpacked sizes, extension counts, and
   per-file hashes are in the corpus manifest.
3. Add deterministic generated files for controlled size/compressibility
   sweeps, and optionally Kenney RPG Base for a clearly CC0 small-asset set.
   Synthetic fixtures provide repeatable controls but must not be reported as
   representative real-world performance.

Do not commit downloaded benchmark data. The corpus record includes exact
URLs, version identifiers, matching published and local archive hashes,
included-path rules, project notices, and a per-file manifest. Keep project
license files and the 3D demo's CC0 checker notice with the extracted inputs.
