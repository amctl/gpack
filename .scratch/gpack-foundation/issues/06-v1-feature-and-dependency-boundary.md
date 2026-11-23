# Set the v1 feature and dependency boundary

Type: grilling
Status: resolved
Blocked by: 01, 02, 03, 04, 09, 15

## Question

Given the product contract, format/access findings, Goose boundary, threat
model, and experiment results, decide the v1 commands and library surface,
codec and hash requirements, deduplication scope, metadata policy, native
dependencies, and explicit deferrals. Prefer a small first release that can
validate the core runtime use case.

## Answer

V1 provides `pack`, `list`, and `verify` CLI commands. The runtime library opens
a read-only archive and looks up a complete asset by normalized path. It
supports four concurrent reads by default, with a configurable 32 MiB default
limit on each asset's uncompressed size; callers may raise that limit when
their workload needs larger assets. Byte-range reads are outside the runtime
contract.

Use one pinned Zstandard 1.5.7 build at level 3, compiled from pinned upstream C
source as part of the native toolchain. Enable the Zstandard frame content
checksum. If a Zstandard frame is not smaller than its source, store the asset
raw and mark its codec in the asset record. Store IEEE CRC32 for every
uncompressed asset and for archive metadata (header and index); verification
checks both metadata and asset content. These checks detect accidental
corruption and do not provide authenticity. Promise byte identity for the same
inputs, options, and exact pinned codec build; verify cross-platform output
before making a cross-build identity promise.

Do not implement content deduplication in v1. Preserve the resolved metadata
policy: normalized safe paths and derived size/offset/codec/checksum fields,
with no source timestamps or permissions. Defer extraction/unpack commands,
byte-range reads, stable asset IDs, partial archive updates, filesystem
mounting, legacy import/export, additional codecs, and deduplication. See the
[H2 framing measurements](../../../docs/research/experiments/h2-frame-granularity/results.md),
[H3 pack results](../../../docs/research/experiments/h3-native-streaming-boundary/results.md),
and [H3 runtime results](../../../docs/research/experiments/h3-runtime-lookup/results.md).
