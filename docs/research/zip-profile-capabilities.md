# Restricted ZIP profile capabilities

Status: capability source review. The later Goose implementation comparison
and its scoped results are in
[restricted-zip-comparison/results.md](experiments/restricted-zip-comparison/results.md).

## Scope

The accepted [gpack v1 specification](../product/spec.md) packages a directory
of regular files into a deterministic read-only archive. Runtime code validates
the index and reads a complete asset by normalized path, using positional I/O
with a default 32 MiB per-asset limit and four concurrent reads. The spec
explicitly records the selected archive contract. This note describes what ZIP
can express and what a Goose reader still needs to decide and enforce; it is
not the performance comparison.

PKWARE’s [APPNOTE 6.3.10](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
defines ZIP as a general interoperable container, permits optional compression,
encryption and extensions, and says applications may define additional
profile information. The format is therefore broader than the narrow profile
that would be suitable for this comparison.

## Capability comparison

| Requirement | ZIP / ZIP64 capability | Policy or implementation still needed in Goose |
|---|---|---|
| Stream creation | Local headers and payloads are followed by the central directory at the end. A data descriptor can carry CRC and sizes after the payload to facilitate streaming output (APPNOTE §§4.3.5, 4.3.9). | Choose descriptor rules, buffering and write strategy; reject unsupported records/features. A writer can emit to non-seekable output, but that says nothing about throughput. |
| Indexed random access | Every member has a central-directory entry including compressed/uncompressed sizes and the local-header offset; EOCD (or ZIP64 EOCD) describes the directory’s count, size and offset (APPNOTE §§4.3.12–4.3.16). A reader can seek to the directory and then to a member. ZIP64 expands sizes/offsets/counts. | Validate offsets and ranges against the actual archive; decide how to handle prepended data, split archives, duplicate names, directory encryption/compression and malformed or ambiguous records. Random access is a structural capability, not a performance result. |
| Unicode paths | ZIP has a UTF-8 general-purpose flag and Unicode path extra field; legacy filename encoding has interoperability history (APPNOTE §§4.4.4, 4.6.9; [Python `zipfile` docs](https://docs.python.org/3/library/zipfile.html)). | Define one accepted encoding/profile (prefer UTF-8 flag), reject malformed encodings and conflicting metadata, then enforce gpack’s UTF-8 relative `/` paths, no NUL/backslash/empty/`.`/`..` components, case-sensitive lookup, and duplicate canonical-byte rejection. ZIP does not define gpack’s safe path contract. |
| Raw / DEFLATE, checksums | Method 0 stores bytes; method 8 is DEFLATE and is described as the default used by most ZIP applications (APPNOTE §§4.1.3, 4.4.5). ZIP requires CRC-32 integrity for each file (§4.1.5). Each member can independently be stored or compressed (§4.1.8). | Restrict methods to 0 and 8, disable encryption, and define CRC verification behavior. ZIP CRC-32 and gpack’s per-asset CRC32 serve accidental-corruption detection; neither authenticates content. Comparing ZIP DEFLATE with gpack Zstandard also compares different codecs, not just container indexes. |
| Bounded index parsing | Central-directory records and optional extra fields have explicit lengths; ZIP64 supports very large entry counts and directories (APPNOTE §§4.3.12–4.3.16). The format does not impose gpack’s 64 MiB / one-million-entry bounds. | Before allocation, cap archive size, directory byte size, entries, filename/extra-field lengths and decoded path length. Check every record boundary, arithmetic operation, local-header reference, range and overlap. Reject unsupported ZIP64/extra-field variants rather than interpreting them partially. |
| Deterministic output | ZIP records include timestamps, flags, creator/version and platform attributes, comments, extra fields, ordering and compression metadata (APPNOTE §§4.3.7, 4.3.12). The format does not promise identical archive bytes for identical assets. | Fix timestamps, attributes, flags, field order, allowed extra fields, comments, encoding, member ordering, ZIP64 policy, DEFLATE implementation/version/level, and data-descriptor choice. Then compare repeated output hashes. This is a profile and writer guarantee, not an inherent ZIP property. |
| Complete asset reads | Stored and DEFLATE members can be decoded as a whole; ZIP records carry compressed size, uncompressed size and CRC. [Python’s official library docs](https://docs.python.org/3/library/zipfile.html) expose member streams and `testzip()` reads members checking CRC and headers. | For Goose, stream exactly the declared compressed extent, cap decoded output, require exactly the declared uncompressed size and successful end-of-stream, then verify CRC before returning bytes. Decide whether API may expose partial bytes before verification; gpack v1 promises complete-asset reads. |
| Per-entry limits / concurrency | ZIP has per-entry size fields, with ZIP64 larger values; the format sets no application memory cap and promises no concurrent reader behavior. | Enforce gpack’s configurable per-entry ceiling (32 MiB default) before allocation/decode; define total concurrent memory budget and four-read default. Use independent positional reads or safe handle synchronization, and test concurrent reads. These are Goose runtime properties, not ZIP format guarantees. |

Python’s library documentation is useful as an implementation example, not as a
format guarantee: it documents ZIP64 support, seekable input for reading,
writing to unseekable streams, per-member stream APIs, and supported codecs.
The exact reader must be the Goose implementation under evaluation; library
behavior should not be substituted for it.

## Candidate restricted profile for an experiment

Use a single-volume, non-encrypted archive with no archive/member comments,
no directory entries, UTF-8-flagged normalized member names, methods 0 or 8
only, and no unrecognized extra fields. Permit ZIP64 only when required by
the same test corpus. Emit sorted path bytes, fixed timestamps and attributes,
fixed flags and field order, and a pinned DEFLATE implementation and level.
For streaming pack, use data descriptors consistently. Reader caps should
match gpack’s 64 MiB index, one-million entries and 32 MiB default asset limit,
with the same four concurrent reads; enforce the same path, size, overlap and
integrity rejection rules.

These are experiment controls, not a proposed replacement for the product
contract. The profile’s minimal extra-field rule needs validation against the
chosen ZIP64 and UTF-8 writer behavior. Define whether CRC must be checked on
every read or only by `verify`, and ensure both implementations use equivalent
verification semantics.

## Apples-to-apples controls and open questions

- Use identical path/byte inputs, including the selected real corpus and edge
  cases; compare full asset reads and correctness before timing.
- Keep compression comparisons explicit: ZIP stored versus gpack raw isolates
  container overhead most closely; ZIP DEFLATE versus gpack Zstandard compares
  the candidate end-to-end codec profiles. Report archive bytes, pack time,
  full-read throughput/latency and peak memory separately.
- Implement or prototype both readers in Goose with comparable positional I/O,
  CRC work, API behavior, build mode, and four-reader workload. Record compiler,
  Goose, native library and codec versions/settings. Alternate paired runs on
  the same host and report variability; do not infer performance from format
  structure or Python-library behavior.
- Test determinism across repeated builds, Unicode and unsafe paths, duplicates,
  malformed/truncated central directories, ZIP64 boundaries, CRC errors,
  inflated-size limits, overlapping/out-of-range payload references, and
  concurrent reads.
- Decide treatment of duplicate member names and local-header/central-directory
  disagreement; whether ZIP64 is allowed unconditionally or only above the
  classic limit; the exact accepted extra fields; and whether the reader must
  reject multi-disk, self-extracting/prefixed, encrypted, or centrally
  encrypted archives.

No source evidence here establishes that a restricted ZIP profile will be
faster or slower than gpack. That remains an empirical question.

## Sources

- PKWARE, [APPNOTE.TXT: .ZIP File Format Specification, version 6.3.10](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT), especially §§4.1, 4.3–4.6 and ZIP64 records.
- Python Software Foundation, [Python `zipfile` library documentation](https://docs.python.org/3/library/zipfile.html), for an official library example of ZIP64, stream writing, member reads, and codec support.
