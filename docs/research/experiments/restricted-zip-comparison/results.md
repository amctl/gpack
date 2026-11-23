# Restricted ZIP comparison results

Status: complete for the measured Linux host and workloads; this does not
establish a general format winner.

## Correctness gate

All three identical-input workload comparisons passed Goose full-read source
CRC checks for GPack raw, product GPack Zstandard/raw, ZIP STORED, and ZIP
DEFLATE. The five-entry edge corpus passed with empty, nested, UTF-8, and
case-distinct paths. Four-reader runs completed for every timed workload.
ZIP `unzip -t` checks passed for every generated archive. Repeated builds were
byte deterministic within each format and arm.

The Goose ZIP reader rejected: truncated EOCD and central directory, malformed
central signature, absolute/traversal/backslash/NUL paths, duplicate paths,
unsupported method, invalid and out-of-range local-header references,
overlapping payload ranges, central/local size mismatch, corrupt payload and
descriptor CRC, a ZIP64-required size sentinel, and a 32 MiB + 1 asset. These
are representative malformed-input fixtures, not an exhaustive parser fuzz
campaign.

## Method

Three arms were measured on the same sorted source files and manifests:

1. **Container:** GPack raw-only versus ZIP STORED.
2. **Product codec profile:** product GPack Zstandard level 3 with raw fallback
   versus ZIP DEFLATE level 3.
3. ZIP STORED and GPack raw results also provide independent baselines for
   interpreting the codec-profile arm.

Each workload had five paired pack runs and five paired reader runs, with
format order alternated. Readers used Goose, positional reads, four workers,
full-asset CRC checks, and a 32 MiB default read limit. Pack and reader peak
RSS are process peak RSS from GNU `time`. Latency is per full-asset read; p50
and p95 are calculated over assets in the run. All paired observations,
archive hashes, workload manifests, environment details, and min/median/max
summaries are in [results.json](results.json). The artifact includes each
source CRC manifest's SHA-256 so the recorded archive results bind to the exact
path/CRC input list used for validation and timing.

Workloads:

| Workload | Files | Source bytes |
| --- | ---: | ---: |
| Godot 4.7 selected real corpus | 63 | 1,197,336 |
| Deterministic mixed workload | 579 | 137,512,216 |
| Godot 4.7 Material Testers project | 109 | 133,365,708 |

## Results

Archive size is bytes. Pack time is median seconds. Lookup throughput is MiB/s.
Parse time is median milliseconds. Pack and reader RSS are median KiB.
Per-asset p50/p95 latencies are milliseconds.

### Container arm: GPack raw versus ZIP STORED

| Workload | Format | Archive bytes | Pack s | Pack RSS KiB | Parse ms | Read MiB/s | p50 / p95 ms | Reader RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Godot real | GPack raw | 1,202,379 | 0.018 | 3,576 | 0.126 | 161.4 | 0.004 / 0.101 | 3,520 |
| Godot real | ZIP STORED | 1,208,064 | 0.018 | 3,708 | 0.286 | 282.7 | 0.003 / 0.070 | 3,752 |
| Mixed | GPack raw | 137,553,714 | 0.340 | 3,760 | 0.208 | 1,255.4 | 0.009 / 0.009 | 133,832 |
| Mixed | ZIP STORED | 137,602,046 | 0.345 | 3,844 | 1.175 | 1,320.8 | 0.008 / 0.023 | 134,044 |
| Material Testers | GPack raw | 133,373,582 | 0.306 | 3,664 | 0.066 | 1,482.7 | 0.004 / 8.389 | 92,728 |
| Material Testers | ZIP STORED | 133,382,650 | 0.309 | 3,740 | 0.157 | 1,503.5 | 0.004 / 8.311 | 92,844 |

Raw GPack is smaller by 5.6 KiB, 47.2 KiB, and 8.9 KiB on these workloads.
Those small differences are consistent with its single index and lack of ZIP
local headers and data descriptors. Pack time, throughput, and RSS are close
in the larger workloads; neither reader has a material measured advantage in
this arm. The small workload throughput is especially sensitive to run noise.

### Product codec arm: GPack Zstandard/raw versus ZIP DEFLATE

| Workload | Format | Archive bytes | Pack s | Pack RSS KiB | Parse ms | Read MiB/s | p50 / p95 ms | Reader RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Godot real | GPack Zstandard/raw | 1,118,384 | 0.031 | 6,808 | 0.129 | 211.9 | 0.007 / 0.132 | 3,836 |
| Godot real | ZIP DEFLATE | 1,112,898 | 0.042 | 5,048 | 0.275 | 155.2 | 0.087 / 1.081 | 7,668 |
| Mixed | GPack Zstandard/raw | 70,375,233 | 0.542 | 8,424 | 0.187 | 1,377.4 | 0.009 / 0.010 | 134,020 |
| Mixed | ZIP DEFLATE | 71,004,327 | 1.190 | 5,152 | 0.522 | 1,334.6 | 0.025 / 0.028 | 138,032 |
| Material Testers | GPack Zstandard/raw | 114,083,027 | 0.784 | 8,508 | 0.069 | 1,133.9 | 0.009 / 12.595 | 106,756 |
| Material Testers | ZIP DEFLATE | 112,402,059 | 1.981 | 5,064 | 0.148 | 814.3 | 0.042 / 13.833 | 96,880 |

On the mixed workload GPack produced an archive 0.9% smaller, packed about
2.2 times faster, read about 3% faster, and used about 4 MiB less reader RSS.
On Material Testers, ZIP DEFLATE produced an archive 1.5% smaller and used
about 9.6 MiB less reader RSS; GPack packed about 2.5 times faster and read
about 39% faster. The small real workload favored ZIP DEFLATE slightly on
size, while GPack had faster reads and lower reader RSS. This is evidence that
codec and corpus content change the tradeoff, not that either format wins
generally.

## What the custom format buys here

The container-only arm shows a small, repeatable size saving for the custom
single-index representation, with similar pack and full-read costs on the two
larger workloads. The product-profile arm shows that GPack's selected
Zstandard/raw policy can retain ZIP-like size while improving pack/read cost
on the mixed workload. On the larger real project ZIP DEFLATE was smaller and
had lower reader RSS, while GPack read faster and packed faster. ZIP STORED
also offers very fast packing and reads at nearly raw size.

So the demonstrated value is a compact, Goose-owned index and the selected
codec profile's tradeoff on these named workloads. Interoperability and the
small raw-container size advantage are real but modest. These results alone
do not establish that maintaining a custom format is better for every project;
ZIP's tooling ecosystem remains a meaningful benefit, while ZIP safety and
resource policy still require a deliberately constrained implementation.

## Scope and deviations

- The ZIP profile is classic single-disk ZIP only. ZIP64 is rejected; the
  tested corpora fit classic fields. ZIP64 writer/reader behavior remains
  unimplemented and unmeasured.
- The writer emits data descriptors and supports separate STORED and DEFLATE
  arms. It does not perform per-entry STORE fallback inside the DEFLATE arm.
- DEFLATE level 3 uses system zlib-ng 1.3.1. The native shim is research-only;
  it is not linked into the product target.
- The raw GPack writer is a research-only Goose pack path using the product
  v1 encoder/reader contract. It exists to isolate container overhead and is
  not a product CLI option.
- Results are from one Linux host, Goose v2026.4, GCC 16.2.1, Intel Core Ultra
  7 255H, and 32 GiB RAM. They do not validate macOS/Windows or establish
  cross-platform archive identity.
- The deterministic mixed workload is generated and the real projects are
  Godot assets. Other asset distributions, storage devices, cache states, and
  reader mixes may change the result.
