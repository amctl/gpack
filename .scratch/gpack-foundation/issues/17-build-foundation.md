# Bootstrap the Goose/native build foundation

Type: task
Status: resolved
Blocked by: 08

## Goal

Create the package and native build skeleton from the canonical tree in
`docs/product/architecture.md`. Pin Goose v2026.4 and vendor Zstandard 1.5.7
with its license/source checksum. Build the static native target through
Goose's CMake sidecar on Linux/GCC, macOS/Apple Clang, and Windows/MSVC.

## Acceptance

- The Goose library package and thin CLI root compile on each target.
- The C ABI header is included by the native target and Goose build, with
  compile-time signature/layout checks.
- Shared scripts expose format, check, build, and test entrypoints; CI invokes
  those scripts on native workers for all three platforms.
- No archive parsing, writing, or product behavior is added in this ticket.

## Answer

Added the Goose library package and thin CLI root, a shared C ABI header, an
ABI probe linked to vendored static Zstandard 1.5.7, provider-neutral format /
check / build / test commands, and a Linux/macOS/Windows CI matrix pinned to
the Goose v2026.4 source commit. The vendored source archive SHA-256 is
`eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3`; upstream
license files and provenance are retained.

Local validation passed Goose format and type checks, built the thin CLI, and
compiled the ABI probe C source with strict GCC warnings. Full native linking
could not run on this host because it has no C++ compiler, which the upstream
Zstandard CMake project requires. macOS and Windows builds remain for the
configured native CI matrix; no platform result is claimed before that
workflow runs. No archive behavior was introduced.
