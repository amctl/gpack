# Harden input scanning, limits, and atomic output

Type: task
Status: resolved
Blocked by: 19, 20

## Goal

Complete the pack safety contract: deterministic recursive scan, non-regular
input rejection, safe collision handling, detected source-mutation failure,
bounded reads, and atomic archive finalization.

## Acceptance

- Symlinks, unsupported file types, invalid paths, and duplicate canonical
  paths fail with actionable errors.
- The 32 MiB default per-asset limit is configurable at runtime; four reads are
  in flight by default and tests verify the configured bound.
- Packing writes a sibling temporary file, flushes it, replaces the output
  only after success, and removes temporary output on failure.
- Tests cover interrupted writes and existing destination behavior on all
  supported platforms.

## Answer

The scanner rejects unsupported filesystem entries and unsafe paths, sorts
canonical UTF-8 asset paths, and rejects duplicate paths. Runtime archive open
accepts a caller-selected per-asset read cap, with the 32 MiB default; the
read-request API supports independent positional reads and tests exercise four
workers and the configured cap. Packing now creates an exclusive temporary
file beside the destination, writes and flushes the complete archive, closes
it, and atomically replaces the destination. All failure paths remove the
temporary file. The mutation fixture interrupts a directory pack and confirms
the existing destination survives and no temporary file remains.

Validation: Goose format/type checks, strict native C compilation, and the
Linux Goose end-to-end pack/read test passed. The test exercises atomic
replacement and preservation after a detected source mutation. macOS and
Windows execution remains part of the issue 23 CI/release gate.
