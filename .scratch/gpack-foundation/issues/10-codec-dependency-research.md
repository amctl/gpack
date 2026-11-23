# Research codec options for reproducible desktop builds

Type: research
Status: resolved

## Question

Using official Zstandard and LZ4 specifications, API documentation, source,
release/build documentation, and licenses, compare whether either codec is a
good v1 dependency for whole-asset runtime reads on Linux, macOS, and Windows.
Cover independent-frame behavior, corruption checks, output determinism under
pinned version/settings, native build/distribution requirements, and the
smallest useful codec surface. Separate codec checks from gpack's archive
integrity contract. Record sourced facts, implications, and unresolved choices
in one concise research note.

## Answer

Zstandard and LZ4 both support independent frames and optional non-cryptographic
checksums, so either can serve whole-asset reads. Zstandard documents
same-build/version reproducibility when relevant settings are fixed; LZ4's
official docs do not promise bit-identical output across versions. Both have C
libraries with static build options and suitable permissive licensing for the
library. Keep raw storage as the baseline and benchmark one codec against it;
the representative corpus must choose whether compression is worth the added
dependency. Exact version, checksum coverage, and cross-platform byte identity
remain open. See
[`docs/research/wayfinder-codec-options.md`](../../../docs/research/wayfinder-codec-options.md).

## Comments

- Issue 06 later selected Zstandard 1.5.7 at level 3, static from pinned
  upstream source, with raw fallback, frame checksums, per-asset CRC32, and
  metadata CRC32. Cross-platform golden output remains to be verified.
