# Codec options for gpack v1

Checked 2026-11-23 against official Zstandard and LZ4 specifications, API/build
documentation, source, and license files. This is the primary-source evidence
note for Wayfinder ticket 10. The selected codec policy is now recorded in
[the v1 product spec](../product/spec.md) and issue 06; H2/H3 measurements are
separate from this source review.

## Findings from primary sources

| Concern | Zstandard | LZ4 |
|---|---|---|
| **Whole-asset framing** | Each Zstandard frame is independently decodable; concatenated frames decode in sequence. A gpack index could point directly to one frame per asset. The seekable extension adds a frame jump table for byte-range access inside large streams, which is unnecessary if v1 reads complete assets. [Format spec](https://github.com/facebook/zstd/blob/dev/doc/zstd_compression_format.md), [seekable format](https://github.com/facebook/zstd/blob/dev/contrib/seekable_format/README.md) | LZ4 Frame is a portable stream format. Frames are independent; set block mode to independent when parallel/block seeking matters. With whole-asset reads, one frame per asset avoids cross-asset decode work. [Frame spec](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md), [frame API](https://github.com/lz4/lz4/blob/dev/lib/lz4frame.h) |
| **Corruption checks** | Optional frame content checksum is 32 bits, derived from XXH64 over decoded content. It detects accidental corruption but is not cryptographic authenticity. The API leaves checksum generation disabled by default, so enable it explicitly if relied on. [Format spec](https://github.com/facebook/zstd/blob/dev/doc/zstd_compression_format.md), [API flags](https://github.com/facebook/zstd/blob/dev/lib/zstd.h) | Optional content checksum is XXH32 over decoded content; optional block checksum detects corruption in each compressed block. Both are non-cryptographic. [Frame spec](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md) |
| **Reproducible output** | The official maintainer answer says output is reproducible for fixed source data, compression level, binary version, and thread count, but exact output is not guaranteed across release versions. Advanced settings must also be fixed. This aligns with the user's pinned-codec-build contract, provided the build and all relevant parameters are pinned and verified. [Upstream maintainer clarification](https://github.com/facebook/zstd/issues/999) | The official frame and API docs define valid output and parameters but do not state a bit-identical compressor-output guarantee across library versions or platforms. A pinned exact build/settings plus gpack golden-output checks is prudent; cross-version bit identity should not be promised without evidence. [Frame spec](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md), [API](https://github.com/lz4/lz4/blob/dev/lib/lz4frame.h) |
| **Native build / distribution** | Official project supports Make and CMake, including static and shared library builds. Its reference implementation is C. [Build docs](https://github.com/facebook/zstd/blob/dev/README.md), [CMake options](https://github.com/facebook/zstd/blob/dev/build/cmake/lib/CMakeLists.txt) | Official project supplies Make, CMake, Meson, and Visual Studio builds; the library is C. It is commonly available through platform package managers, but system versions differ. [Build docs](https://github.com/lz4/lz4/blob/dev/README.md), [build directory](https://github.com/lz4/lz4/tree/dev/build) |
| **License** | Zstandard library offers BSD-style or GPLv2 licensing; preserve the chosen license and notices in source and binary distributions. [License](https://github.com/facebook/zstd/blob/dev/LICENSE) | The `lib/` library is BSD 2-Clause. The command-line programs are GPL-2.0-or-later; gpack would link/use the library, not copy the CLI. [License split](https://github.com/lz4/lz4/blob/dev/LICENSE), [project README](https://github.com/lz4/lz4/blob/dev/README.md) |

The bundled Goose v2026.4 supports C integration through `.build` sidecars
and CMake projects; this gives both codecs a plausible native integration
path, but it does not prove that one release/build recipe works on all three
gpack targets. See the local [Goose package guide](../../goose-bin/docs/packages.md)
and the [Goose boundary note](wayfinder-goose-boundary.md).

## Implications for the selected v1 contract

- The user selected **whole-asset reads by normalized path**, not byte-range
  reads. A per-asset frame is the simpler first comparison. Zstandard seekable
  framing should not be added just for cross-asset lookup.
- Both codecs can add accidental-corruption checks at the frame level. gpack
  still needs to specify checksum coverage for archive metadata/index and must
  not describe a codec checksum as authenticity protection.
- Zstandard provides a clear same-version reproducibility statement, but
  requires pinning the exact release and compression settings. Pinning only a
  broad version range is insufficient. Verify the required guarantee across
  Linux, macOS, and Windows builds before calling archive output cross-platform
  reproducible.
- LZ4's library license and build options are straightforward, and its frame
  checksum is suitable for accidental corruption detection. The public docs do
  not give the same explicit bit-reproducibility guarantee as Zstandard.
- Goose builds threaded programs through a real C compiler. Bundling one pinned
  static codec source release can reduce runtime dependency variation but
  increases source/build and license-maintenance work. Linking arbitrary system
  codec libraries reduces vendored source but weakens the pinned-build
  reproducibility contract.

## Selected v1 policy

V1 uses pinned Zstandard 1.5.7 at level 3, built statically from vendored
upstream source. It enables frame content checksums and stores raw bytes when a
complete Zstandard frame would not reduce size. Each asset also receives an
IEEE CRC32, and header/index metadata receives CRC32. This was selected in
Wayfinder issue 06 after the H2 framing study and H3 boundary experiments; it
is not a codec-vs-codec performance comparison.

## Remaining verification

- Verify pinned-build golden output on Linux/GCC, macOS/Apple Clang, and
  Windows/MSVC before claiming cross-build byte identity.
- Update the pin deliberately when security fixes or a measured product need
  justify changing Zstandard, then regenerate and review golden outputs.
- Keep license notices for the bundled upstream C source with source and
  binary distributions.

The source review itself did not benchmark codecs. The later H2/H3 experiments
measured only the selected Zstandard build against raw storage and Goose/C
processing paths.
