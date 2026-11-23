# Validate cross-platform archives and release artifacts

Type: task
Status: open
Blocked by: 17, 20, 21, 22

## Goal

Validate the pinned build and archive contract on native Linux/GCC,
macOS/Apple Clang, and Windows/MSVC workers, then document the tagged release
procedure.

## Acceptance

- All correctness fixtures pass on each platform.
- Golden archive bytes match across platforms for identical inputs/options and
  the pinned codec build; otherwise document and narrow the reproducibility
  guarantee before release.
- Non-ASCII and case-distinct paths pass the cross-platform fixtures.
- Build outputs have no unplanned dynamic Zstandard dependency and include
  required third-party notices.
- The release is produced only from a passing version tag; no release is
  published by this task without user authorization.

## Progress

- The CI workflow already defines native Ubuntu/GCC, macOS/Apple Clang, and
  Windows/MSVC jobs. Added a product-packed golden archive containing raw,
  Zstandard, empty, and UTF-8 path entries; the pack/read fixture now checks
  exact archive bytes, Unicode lookup, and case-distinct paths without relying
  on a case-sensitive host filesystem.
- The build script now checks every executable for a dynamic Zstandard
  dependency and writes the pinned Zstandard `LICENSE` and `COPYING` files to
  `build/THIRD_PARTY_NOTICES/`. Added a tag-based release procedure; it does not
  publish artifacts automatically.
- The full `python scripts/gpack.py ci` run now passes on Linux with the
  production CMake path and installed GCC/G++ toolchain. It built all four
  executables, passed the golden archive, Unicode/case, and correctness
  fixtures, verified no dynamic Zstandard dependency, and checked copied
  notices.
- The macOS and Windows native jobs have not been run from this workspace.
  Keep this issue claimed until CI reports all three native jobs passing and
  the golden archive matches on each platform.
- This checkout has no Git remote configured, and GitHub CLI cannot reach the
  API from this network. Native hosted-runner results therefore cannot be
  inspected or triggered from this environment.
- Native macOS and Windows validation is deferred by the user for later.
