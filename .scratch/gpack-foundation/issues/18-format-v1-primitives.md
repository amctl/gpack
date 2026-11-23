# Implement v1 format primitives and validation

Type: task
Status: resolved
Blocked by: 17

## Goal

Implement explicit little-endian header/index encoding and decoding, canonical
path validation, CRC32, range/overflow checks, and golden fixtures according
to `docs/format/v1.md`.

## Acceptance

- Round-trip header and index bytes match checked-in golden fixtures.
- Reject unsupported versions/codecs, invalid counts, unsafe/duplicate paths,
  nonzero reserved bytes, CRC mismatches, overlapping/out-of-range payloads,
  and truncated/trailing metadata.
- Check every offset/size calculation before allocation or access.
- Goose owns all format semantics; the C target contains no GPack records.

## Answer

Implemented Goose-owned CRC32, explicit little-endian header/index codecs,
header and index validation, canonical UTF-8 path checks, entry ordering and
payload-range validation. Index encoding preflights entry and byte limits
before allocating. Payload ranges are now explicitly required in record order
in the normative spec, allowing linear-time overlap validation instead of an
unbounded pairwise scan.

Checked-in hex fixtures cover an empty archive header/index and one raw entry.
The Goose format test reads those fixtures and checks exact encoded bytes. It
also exercises CRC32's standard `123456789` vector, malformed versions,
reserved bytes, bad checksums, count mismatches, truncation/trailing bytes,
invalid UTF-8 and path forms, unknown codecs, duplicate paths, overlap, and
out-of-range payloads.

Validation passed Goose format/type checks, the built Goose format test, and
`git diff --check`. The test does not use the native ABI, so it ran on this
host despite the missing C++ compiler noted in issue 17.
