# Verify the Goose implementation boundary

Type: research
Status: resolved

## Question

Using the exact bundled Goose toolchain and its primary documentation/source,
verify the language, queue, filesystem, package, C ABI, build, and platform
constraints relevant to gpack. Compare an all-Goose implementation, a narrow
native streaming/codec layer, and a native implementation with Goose policy.
Recommend the smallest maintainable seam and list assumptions that need a
prototype or experiment. Cite primary sources in a consolidated research note.

## Answer

The exact bundled baseline is Goose v2026.4, runtime `dce889723a23`, source
revision `dec4bd827a1da10041febd7eb583fe3c4f96a2b9`. Its standard file API is
whole-file oriented; thread queue messages are copied flat values and queue
limits count messages; typed C FFI and `.build` sidecars are available; threaded
programs require a real C compiler build. This supports a narrow native
streaming/codec boundary as a candidate if v1 requires bounded-memory handling
of large assets, while Goose owns format policy and checked parsing. It does
not prove that this split is needed or performant; H1/H3 and platform validation
remain. See
[`docs/research/wayfinder-goose-boundary.md`](../../../docs/research/wayfinder-goose-boundary.md).
