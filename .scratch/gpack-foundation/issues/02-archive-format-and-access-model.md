# Choose the archive access and framing model

Type: research
Status: resolved

## Question

Against primary specifications and implementations, compare a new indexed
gpack format with ZIP/ZIP64 and other relevant asset-container approaches for
the confirmed v1 workflow. Resolve whether custom format complexity is
justified, and identify the smallest framing/index model that supports the
required streaming build, random reads, validation, and compatibility promise.
Record source-linked findings in the canonical research area.

## Answer

Primary-source comparison found that ZIP/ZIP64 already supports sequential
construction and indexed lookup. Random access alone therefore does not
justify a custom format. A new format remains a candidate if the runtime
contract needs properties a restricted ZIP profile cannot provide simply,
such as stable IDs, bounded parsing, a narrower codec surface, or runtime API
fit. Compare restricted ZIP, custom whole-file entries, custom chunked entries,
and embedded assets if independent distribution is not needed. The research
note records the evidence and remaining questions:
[`docs/research/wayfinder-format-access.md`](../../../docs/research/wayfinder-format-access.md).

## Comments

- Subsequent product decision: issue 01 records the user's selection of a new
  versioned gpack format. Issue 06 narrows it to per-asset raw/Zstandard
  entries; issue 08 captures the v1 wire contract. The comparative ZIP benefit
  remains an explicit risk, not an evidence-backed performance claim.
