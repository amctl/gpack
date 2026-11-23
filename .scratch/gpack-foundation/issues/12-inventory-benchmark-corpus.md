# Inventory the pinned Godot benchmark corpus

Type: task
Status: resolved
Blocked by: 05

## Question

Acquire only the candidate Godot 4.7 demo project archives needed for one
eligible 2D, 3D, and audio demo. Verify published SHA-256 values, inventory
candidate regular-file counts and size/type distributions, review project and
embedded third-party notices, then select the eligible project nearest each
category's median regular-file count. Record exact source URLs, release and
hashes, selected names, included paths, sizes, per-file hashes, and notices in
a reproducible corpus manifest. Do not commit corpus binaries. Leave unresolved
license candidates out and record the exclusion reason.

## Answer

Pinned the corpus to Godot demo-project release `4.7-6ad6167` (commit
`6ad6167`). Inventorying every project directory in the source snapshot found
27 2D projects (median 22 regular files), 32 3D projects (median 26.5), and 9
audio projects (median 12). After reviewing the median candidates and their
notices, select:

- `2d/kinematic_character`: 22 source-tree files; the distributed project ZIP
  contains 23 files including its MIT `LICENSE.md`.
- `3d/lights_and_shadows`: 26 source-tree files; the distributed project ZIP
  contains 27 files including its MIT `LICENSE.md` and CC0 `checker.LICENSE.md`.
- `audio/mic_record`: 12 source-tree files; the distributed project ZIP
  contains 13 files including its MIT `LICENSE.md`.

The three project ZIPs passed archive integrity checks. Their downloaded SHA-256
values exactly match the pinned release metadata:

- `2d_kinematic_character.zip`: `898a8d4b89d5fcce4fbe6cccbf1b7c89fc34d0d0ca422a217abc3d6ffb97aa05`
- `3d_lights_and_shadows.zip`: `b2a7d5922575833ff31476746ec3f7cf5ed9db4221824380e8cab0df2aeadab3`
- `audio_mic_record.zip`: `36d728ec24fff6183242e4207669a35f926e9e04aeb92eb320703f366ba1036f`

In 2D, `kinematic_character` and `particles` tie at 22; both have no
project-specific third-party notice, so the path tie-break selects
`kinematic_character`. In 3D, the 26-file `global_illumination` project includes
a CC BY 4.0 model attribution. `lights_and_shadows` has one CC0 checker notice;
the equally close 27-file `soft_body_physics` has a CC0 checker plus three
Poly Haven CC0 textures. `lights_and_shadows` has the lower third-party asset
and notice burden. In audio, `mic_record` and `spectrum` tie at 12 and both
projects are MIT licensed; the path tie-break selects `mic_record`. All
selected project files and notices are retained.

The corpus manifest records every category project's file count and every
selected file's size and SHA-256 at
[`docs/research/experiments/godot-4.7-corpus/manifest.json`](../../../docs/research/experiments/godot-4.7-corpus/manifest.json).
Acquisition instructions and notice review are in the adjacent README. Source
and selected ZIPs were kept in `/tmp`; none were added to the repository. No
benchmark experiment has run.
