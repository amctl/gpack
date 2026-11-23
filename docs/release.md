# Release procedure

gpack releases are cut from version tags after the native platform matrix
passes. This repository does not publish releases automatically.

1. Confirm the target commit has a successful `CI / native` matrix run on
   `ubuntu-24.04`, `macos-14`, and `windows-2022`, including the golden archive,
   Unicode/case path, correctness, and static Zstandard checks.
2. Create and push an annotated `vMAJOR.MINOR.PATCH` tag at that exact commit.
   Wait for CI on the tag and stop if any platform job fails.
3. On each native platform, run `python scripts/gpack.py ci` with Goose v2026.4
   available. This builds the CLI and fixtures and writes the Zstandard
   `LICENSE` and `COPYING` files into `build/THIRD_PARTY_NOTICES/`.
4. Distribute the platform CLI together with that notice directory. Record the
   tag, source commit, and artifact hashes in the release notes. Do not claim
   cross-platform byte identity unless the golden checks passed on all three
   platform jobs.

This procedure documents a release; it does not authorize publication. A
maintainer must explicitly approve any release upload or announcement.
