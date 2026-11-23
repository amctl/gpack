# Archive format and runtime access: decision evidence

Status: primary-source research input for Wayfinder ticket 02, checked
2026-11-23. The user subsequently selected a new versioned gpack format; see
the [v1 format contract](../format/v1.md). This note's finding that random
access alone does not establish a product benefit remains a risk until gpack
is compared with a restricted ZIP profile.

## Facts from primary sources

- **ZIP/ZIP64:** PKWARE defines ZIP as a cross-platform interoperable storage
  and transfer format, without prescribing an application-specific use. Its
  archive sequence places each local header and file payload first, followed
  by central-directory records and end records. Data descriptors permit
  streaming creation. The end records locate the central directory; ZIP64 adds
  wider counts, sizes, and offsets when classic fields are too small. This
  supports both sequential construction and indexed lookup, but brings a
  general-purpose format surface and duplicate per-file/local-plus-central
  metadata. [PKWARE ZIP APPNOTE, sections 1.1–1.2 and 4.3–4.4](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
- **Zstandard seekable frames:** Zstd's seekable extension stores independent
  frames and a jump table. A reader can find the relevant frame for a byte
  range without decoding the whole stream. Smaller frames reduce the extra
  decode for small reads but reduce compression ratio and increase table cost.
  Zstd's API also allows frames to be compressed independently and assembled
  with a table, which is compatible with parallel build work. This is a
  compression/indexing mechanism, not a complete archive catalog: it does not
  define asset names, paths, file-to-frame mapping, or extraction rules.
  [Zstd seekable format README](https://github.com/facebook/zstd/blob/dev/contrib/seekable_format/README.md),
  [Zstd seekable API](https://github.com/facebook/zstd/blob/dev/contrib/seekable_format/zstd_seekable.h)
- **Unreal IoStore/Zen Loader:** Epic documents staged `.utoc` metadata and
  `.ucas` data containers. The table of contents describes chunks, while an
  I/O dispatcher loads data by chunk ID through platform-specific backends.
  Epic also documents a deliberate tradeoff: this runtime path is not ordinary
  file/directory search, and asset discovery is handled through an asset
  registry. This is evidence that a game runtime may benefit from an
  application-specific indexed layer, but its offline dependency processing
  and engine integration exceed gpack's proposed scope.
  [Epic Zen Loader documentation](https://dev.epicgames.com/documentation/unreal-engine/zen-loader-in-unreal-engine?lang=en-US)
- **Embedded assets:** Go's standard `embed` facility creates a read-only
  filesystem image in the executable and exposes it via `fs.FS`; this removes
  a separate archive/runtime parser for fixed assets. It is a meaningful
  baseline when assets need no independent updates or external deployment.
  [Go `embed` documentation](https://pkg.go.dev/embed)

## Implications for gpack

The confirmed working target is a game/runtime asset archive with random
access. That makes a seekable index relevant, but does not by itself justify a
new format. ZIP already combines streaming writes and central-directory
lookup, and provides interoperability. A custom format is justified only if
the v1 contract needs runtime properties that a deliberately restricted ZIP
profile cannot provide simply—for example, stable asset IDs, explicitly
bounded index parsing, independently addressable chunks, a narrow codec set,
or a format tailored to the Goose runtime API. Every such gain creates a
format compatibility and maintenance obligation.

The closest useful structural pattern is a sequential payload plus a bounded,
versioned index, with per-asset or per-chunk records that point to independent
decode units. Zstd seekable framing can serve as a component if Zstd is chosen;
it should not be mistaken for the full gpack format. The correct decode-unit
size depends on actual access patterns, file sizes, and small-file prevalence,
so the existing 1 MiB proposal value remains an unvalidated hypothesis.

Before deciding, compare three concrete options against the intended Goose
runtime API: (1) a restricted ZIP/ZIP64 profile; (2) a new indexed gpack format
with whole-file entries; and (3) a new indexed format with independently
framed chunks. Include embedded assets as a product-level alternative if
external updates, independent distribution, or large asset sets are not
requirements.

## Decisions still needed

- Must assets be independently replaced or patched after the executable is
  built? Can the archive be distributed separately?
- Does runtime lookup start from a path/name, stable asset ID, or both? Are
  byte-range reads required, or only whole-asset retrieval?
- Is third-party ZIP tooling or archive interoperability a requirement?
- What are representative asset sizes, counts, and lookup patterns? These
  determine whole-file versus chunk framing and the acceptable index size.
- What concrete runtime or Goose constraint would a custom format solve that a
  restricted ZIP profile and a read-only embedded filesystem cannot?

Until those answers and an experiment over a representative corpus exist, do
not freeze a custom v1 format, chunk size, or codec default.
