# Release procedure

gpack releases are cut from version tags after the native platform matrix
passes. This repository does not publish releases automatically.

1. Confirm the target commit has a successful `CI / native` matrix run on
   `ubuntu-24.04`, `macos-15`, and `windows-2022`, including the golden archive,
   Unicode/case path, correctness, and static Zstandard checks.
2. Create and push an annotated `vMAJOR.MINOR.PATCH` tag at that exact commit.
   Wait for CI on the tag and stop if any platform job fails.
3. On each native platform, run `python scripts/gpack.py ci` and
   `python scripts/gpack.py package` with Goose v2026.4 available (or let
   [`.github/workflows/release.yml`](../.github/workflows/release.yml) run on
   the pushed `v*` tag). This builds and verifies the CLI, writes the Zstandard
   `LICENSE` and `COPYING` files into `build/THIRD_PARTY_NOTICES/`, and
   packages the binary, `LICENSE`, notices, and `.sha256` files into
   `build/dist/`.
4. The tag workflow creates a **draft** GitHub Release after all three platform
   jobs succeed. Review the draft release, artifact hashes, and release notes,
   then publish manually. Do not claim cross-platform byte identity unless the
   golden checks passed on all three platform jobs.

This procedure documents a release; it does not authorize publication. A
maintainer must explicitly approve any release upload or announcement.
