# gpack v1 risk register

| Risk | Likelihood / impact | Current evidence | Mitigation and decision gate |
|---|---|---|---|
| Custom format maintenance is not justified over restricted ZIP | Medium / High | Prior-art review found ZIP already supports streaming plus indexed lookup; current experiments did not compare gpack to ZIP. | Keep v1 format small and versioned. Revisit before stable v1 if the Goose API, corruption contract, or build path does not provide a measured product benefit. |
| Goose runtime throughput misses target | Medium / High | The product v1 reader met the 10% median throughput gate on one Linux host after CRC and small-frame decode optimizations. Other platforms remain unmeasured. | Keep the acceptance scoped to the measured Linux build; issue 23 validates native builds and correctness on macOS and Windows. |
| Cross-platform byte identity is not verified | Medium / High | Measurements ran on one Linux host; Zstandard reproducibility is scoped to a fixed version/build/settings. | Pin Goose and Zstandard; check golden output on Linux/GCC, macOS/Apple Clang, and Windows/MSVC before broadening the guarantee. |
| Unicode and case behavior can differ across source filesystems | Medium / Medium | V1 preserves valid UTF-8 bytes and case, with exact byte lookup; no extraction occurs. | Reject invalid UTF-8 and unsafe components; test non-ASCII paths on all targets. Revisit normalization only with a concrete cross-platform collision requirement. |
| Read limit does not cap total application memory | Medium / High | The configurable 32 MiB limit bounds one uncompressed asset; returned buffers may be retained by callers, and concurrent reads multiply working memory. | Default to four in-flight reads, document ownership and memory formula, and measure upper-bound RSS. Consider a separate aggregate budget if real workloads require it. |
| CRC32 is not authenticity protection | Low / High if misrepresented | The selected checksum detects accidental corruption only. | Document threat boundary. Do not claim tamper resistance, signatures, or authenticity. |
| Source changes during packing | Medium / Medium | Filesystem snapshots are not transactionally consistent across a tree. | Record file identity/size/time before reading, checksum bytes as read, recheck after, fail on detected mutation, and document that callers must keep inputs stable. |
| Atomic replace differs across filesystems/platforms | Medium / High | Native streaming write/flush/replace behavior has only been prototyped on Linux. | Use a temporary sibling on the same filesystem; test flush, close, and replace semantics on all targets before release. |
| Pinned Zstandard source adds update and license work | Medium / Medium | Zstandard 1.5.7 is selected and statically built; security fixes may require a deliberate pin update. | Preserve upstream license notices, record source hash, and make version bumps explicit with golden/reproducibility checks. |
| Per-asset frames do not improve real-corpus read performance | Medium / Medium | H2 found no material framing difference on the small Godot corpus; H3 runtime missed the C throughput gate. | Treat whole-asset frames as the selected API fit, not a performance claim. Keep benchmarks and revisit alternatives if measured use cases fail. |
| Goose/C ABI drift | Medium / High | Goose structs are compiler-generated and not a general stable ABI. | Pin Goose v2026.4; keep one ABI header and compile-time checks; do not expose the internal ABI as a third-party stable interface. |

## Open acceptance gates

- Runtime throughput met the agreed 10% C gap on the measured Linux build;
  cross-platform throughput remains unmeasured.
- Golden output and corruption behavior must pass on all three desktop build
  targets.
- The runtime's four-reader and 32 MiB per-asset defaults need measured peak
  memory on all targets.
- Path collision policy needs non-ASCII and case-sensitive fixtures on Windows
  and macOS before release.
