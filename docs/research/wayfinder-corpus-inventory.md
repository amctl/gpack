# Existing Goose asset corpus: suitability for gpack experiments

Checked 2026-11-23 from the ignored local Goose v2026.4 bundle. This is a
read-only inventory of the sample WAD, not a gpack benchmark or experiment
result.

## Observed sample

The Goose `31_mini_doom` sample describes its input as a supplied Freedoom
E1M1 WAD containing the map, palette, textures, and sprites. As a gpack input,
the bundled WAD is one filesystem file at
`goose-bin/samples/data/freedoom1-e1m1.wad`, 4,789,358 bytes, SHA-256
`244f2818bbe0929cafe8c2f5433bda28cc05f32695aef37b411dc5df0a0a5659`.
Parsing only its IWAD header and 16-byte directory records found 1,220 internal
lumps, 1,220 distinct names, 19 zero-size lumps, and no directory range outside
the file. Lump sizes: 944 are at most 4 KiB, 250 are 4–64 KiB, 7 are 64 KiB–1
MiB, and none exceed 1 MiB. These lumps are not 1,220 separate filesystem
assets; gpack would see the WAD as one 4.8 MB input unless an extraction step
creates files from the lumps.

Source: bundled [`31_mini_doom` sample](../../goose-bin/samples/31_mini_doom.goose),
[sample index](../../goose-bin/samples/README.md), and
[`freedoom1-e1m1.wad`](../../goose-bin/samples/data/freedoom1-e1m1.wad).
The binary remains ignored local research input and is not copied into gpack.

## Implication

As-is, this is a useful single-file fixture for correctness and medium-file
lookup. Its internal lumps could be extracted into a derived many-small-file
fixture, but that requires a documented extraction rule and tests a derived
WAD corpus rather than an actual game asset directory. It is not representative
for large-file streaming, chunk-size tradeoffs, parallel compression
throughput, already-compressed media, or cross-file deduplication. H1/H2/H3
need additional corpora: large compressible files, large incompressible or
already-compressed files, and a realistic mixed game-asset tree. Check
distribution rights before committing or redistributing any external corpus.

No archive build, compression benchmark, or gpack runtime measurement was run.
