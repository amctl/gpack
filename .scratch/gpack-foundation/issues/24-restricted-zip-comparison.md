# Compare v1 with a restricted ZIP profile

Type: research
Status: resolved
Blocked by: 22

## Question

Does the accepted GPack v1 implementation provide a measured product benefit
over a restricted ZIP/ZIP64 profile for the Goose workflow?

## Scope

Use the [source capability review](../../../docs/research/zip-profile-capabilities.md)
and preregistered [comparison protocol](../../../docs/research/experiments/restricted-zip-comparison/protocol.md).
Implement equivalent Goose pack/read paths for the restricted profile and
compare on identical pinned real and mixed corpora. Keep ZIP STORED vs GPack
raw as a container-focused arm and ZIP DEFLATE vs GPack Zstandard/raw as a
separate end-to-end profile arm. Keep ZIP code in a research-only Goose package
and executable; do not add ZIP support or a format selector to the product
package/CLI. Isolate its native DEFLATE dependency from the production target.

## Acceptance

- Correctness and malformed-input gates pass for the ZIP reader, including
  safe paths, duplicate rejection, bounded directory parsing, CRC validation,
  decoded-size limits, and concurrent full-asset reads.
- Repeated ZIP builds are deterministic under the selected pinned writer and
  profile.
- Five paired runs per workload record archive size, pack time, full-asset
  lookup throughput/latency, peak RSS, environment, and raw observations.
- Results distinguish container effects from codec-profile effects and make
  no claim beyond the measured corpus and host.
- Update the research synthesis and product risk with the evidence; retain the
  v1 format choice unless results establish a material workflow benefit and
  the maintenance tradeoff is explicit.

## References

- [ZIP profile capability review](../../../docs/research/zip-profile-capabilities.md)
- [Restricted ZIP comparison protocol](../../../docs/research/experiments/restricted-zip-comparison/protocol.md)

## Answer

The restricted Goose ZIP implementation passed full-read source CRC and
determinism checks across the 63-file Godot real corpus, 579-file deterministic
mixed workload, and 109-file Material Testers project. Edge fixtures covered
empty, UTF-8, nested, and case-distinct paths; malformed-path, duplicate,
truncation, CRC/descriptor, unsupported method, ZIP64-boundary, and 32 MiB
limit rejection passed. Four-reader runs and external `unzip -t` checks passed.

In the container arm, GPack raw was 5.6–47.2 KiB smaller than ZIP STORED on
these workloads, while pack time, lookup throughput/latency, and RSS were
similar. In the codec arm, GPack Zstandard/raw packed and read faster and was
slightly smaller on the mixed workload. On Material Testers, ZIP DEFLATE was
1.5% smaller and used less reader RSS; GPack packed about 2.5 times faster and
read about 35% faster. The small real corpus has sub-millisecond behavior and
visible run variation. These observations describe the named inputs and one
Linux host, not a general winner.

Retain the selected v1 contract for now. The measured custom-format value is
the smaller single-index raw representation and the product codec tradeoff on
the mixed workload; ZIP remains compelling where interoperability, smaller
DEFLATE output, or lower reader RSS matters. ZIP64, macOS/Windows, and a wider
set of target projects remain unmeasured. Full measurements and limitations
are in the [result report](../../../docs/research/experiments/restricted-zip-comparison/results.md)
and [raw results](../../../docs/research/experiments/restricted-zip-comparison/results.json).
