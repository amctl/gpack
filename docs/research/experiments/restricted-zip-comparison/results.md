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
descriptor CRC, ZIP64-required sentinels for member sizes and offsets, EOCD
entry count, and directory size/offset, and a 32 MiB + 1 asset. These are
representative malformed-input fixtures, not an exhaustive parser fuzz
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
| Godot real | GPack raw | 1,202,379 | 0.015 | 3,584 | 0.135 | 185.0 | 0.008 / 0.143 | 3,632 |
| Godot real | ZIP STORED | 1,208,064 | 0.016 | 3,716 | 0.265 | 184.6 | 0.007 / 0.125 | 3,760 |
| Mixed | GPack raw | 137,553,714 | 0.337 | 3,876 | 0.300 | 1,362.2 | 0.009 / 0.010 | 133,948 |
| Mixed | ZIP STORED | 137,602,046 | 0.334 | 3,940 | 0.521 | 1,359.8 | 0.009 / 0.010 | 134,100 |
| Material Testers | GPack raw | 133,373,582 | 0.332 | 3,644 | 0.147 | 1,401.8 | 0.004 / 9.327 | 92,736 |
| Material Testers | ZIP STORED | 133,382,650 | 0.325 | 3,728 | 0.172 | 1,386.1 | 0.004 / 9.638 | 92,956 |

Raw GPack is smaller by 5.6 KiB, 47.2 KiB, and 8.9 KiB on these workloads.
Those small differences are consistent with its single index and lack of ZIP
local headers and data descriptors. Pack time, throughput, and RSS are close
in the larger workloads; neither reader has a material measured advantage in
this arm. The small workload throughput is especially sensitive to run noise.

### Product codec arm: GPack Zstandard/raw versus ZIP DEFLATE

| Workload | Format | Archive bytes | Pack s | Pack RSS KiB | Parse ms | Read MiB/s | p50 / p95 ms | Reader RSS KiB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Godot real | GPack Zstandard/raw | 1,118,384 | 0.018 | 6,820 | 0.126 | 178.1 | 0.018 / 0.162 | 3,844 |
| Godot real | ZIP DEFLATE | 1,112,898 | 0.034 | 4,956 | 0.282 | 81.4 | 0.079 / 1.030 | 7,728 |
| Mixed | GPack Zstandard/raw | 70,375,233 | 0.522 | 8,372 | 0.191 | 1,382.8 | 0.009 / 0.011 | 134,020 |
| Mixed | ZIP DEFLATE | 71,004,327 | 1.185 | 5,164 | 1.105 | 1,349.8 | 0.027 / 0.033 | 138,032 |
| Material Testers | GPack Zstandard/raw | 114,083,027 | 0.825 | 8,616 | 0.063 | 1,034.6 | 0.009 / 13.854 | 106,760 |
| Material Testers | ZIP DEFLATE | 112,402,059 | 2.089 | 4,964 | 0.166 | 741.6 | 0.056 / 15.618 | 97,060 |

On the mixed workload GPack produced an archive 0.9% smaller, packed about
2.3 times faster, read about 2% faster, and used about 4 MiB less reader RSS.
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

- The ZIP profile is classic single-disk ZIP only. ZIP64 archives are
  unsupported; sentinel rejection was checked for member sizes/offsets and
  EOCD directory/count fields. The tested corpora fit classic fields. Full
  ZIP64 read/write support remains unimplemented and unmeasured.
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
