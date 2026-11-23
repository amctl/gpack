# Goose boundary for gpack

Checked 2026-11-23 against the bundled compiler and documentation. The ignored
`goose-bin/` bundle reports `goose v2026.4 (runtime dce889723a23)` and is at
source revision `dec4bd827a1da10041febd7eb583fe3c4f96a2b9`. This pinned local
bundle defines the project baseline; upstream docs are evolving and should be
rechecked when the toolchain is upgraded.

## Facts in the bundled toolchain

- **Threads do not share Goose memory.** Each `thread_fn` runs as a separate
  program with its own data stacks and copies of the globals it uses. Arguments
  and queue values must be flat, with no references or slices. Queue transfer
  copies the flat value. See [`reference.md`](../../goose-bin/docs/reference.md#22-threads)
  and [`goose_spec.md`](../../goose-bin/docs/goose_spec.md#112-concurrency).
- **Queue limits count messages.** `qlimit<T>(n)` caps a type's queue at `n`
  messages. `qput` does not wait for room; it returns `false` if full. A queue
  carrying variable-size chunk bytes therefore has no aggregate byte cap just
  because its message count is bounded. See the same thread references above.
- **The standard file API is path-based and whole-file oriented.** The API is
  documented in [`stdlib.md`](../../goose-bin/docs/stdlib.md#os): `read_file` appends the
  whole file, and writes are whole-buffer operations. The documented surface
  has no persistent file handle or positional file read/write function. A
  local search for `pread`, `read_at`, `open_file`, and `write_at` in the
  bundled stdlib/docs found no such API. `write_file_atomic` atomically replaces
  one whole file, which does not provide streaming archive output.
- **Goose has a supported direct C boundary.** A fully typed top-level
  `extern fn` maps to a C symbol; Goose slices cross as pointer/length pairs.
  A program may provide C sources, include paths, flags, and libraries in a
  `.build` sidecar beside its root Goose program. See
  [`reference.md`](../../goose-bin/docs/reference.md#24-calling-c-and-being-called-from-c),
  [`goose_spec.md`](../../goose-bin/docs/goose_spec.md#710-extern-fn), and
  [`packages.md`](../../goose-bin/docs/packages.md#3-a-program-with-c-of-its-own).
- **Threaded programs need a real C compiler build.** The bundled docs state
  that `goose run` refuses programs that start threads because its in-process
  TinyCC backend cannot provide the worker data-stack TLS. `goose build` uses
  a machine C compiler. A build sidecar supports platform-specific settings
  for Windows, Linux, and macOS. See
  [`command_line.md`](../../goose-bin/docs/command_line.md#2-running-a-program)
  and [`packages.md`](../../goose-bin/docs/packages.md#3-a-program-with-c-of-its-own).
- **The standard library documents Windows, Linux, and macOS support** for
  resource-path discovery and platform runtime behavior. This is evidence of
  Goose support, not a gpack compatibility guarantee for every filesystem,
  codec, or C dependency. See [`stdlib.md`](../../goose-bin/docs/stdlib.md#os).

## Design implication

The evidence supports a **small native I/O boundary as a candidate**, not yet
as a proven requirement for all of gpack. If v1 must process assets larger than
memory with bounded working memory, path-based whole-file `read_file` cannot
meet that requirement by itself. A narrow C interface for opening/closing
files, positional reads/writes, flush/replace, and codec calls could supply the
missing operations while Goose owns archive policy, checked parsing, indexing,
and orchestration. Its ownership rules, error model, and platform parity must
be tested rather than inferred from the existence of `extern fn`.

Do not send chunk-sized payloads through worker queues by default. The language
permits it, but flat-value copies plus message-count-only bounds mean memory
must be controlled separately. A coordinator also must drain out-of-order
results without waiting on one sequence while its queue is full of later
results; otherwise the proposed ordered writer can deadlock. Metadata-only
messages plus bounded native staging are candidates to compare in H1.

## Updated interpretation after the H1/H3 experiments

Wayfinder issues 14 and 16 subsequently tested the proposed seam. Native
streaming I/O and Zstandard reduced pack-side memory substantially on large
controls and met the pack throughput gate. Indexed runtime reads passed
correctness and malformed-input checks, but Goose throughput missed the 10%
gap by 27.4% on the real corpus and 12.1% on mixed. Issue 07 selected a Goose
policy layer with native I/O/codec code and a three-platform build matrix; that
selection is recorded in the [product architecture](../product/architecture.md).

## Remaining validation after this inspection

- Runtime dispatch must be optimized and the paired H3 benchmark repeated
  before runtime performance acceptance (implementation issue 22).
- Golden byte identity, memory defaults, and native file behavior must be
  validated on Linux/GCC, macOS/Apple Clang, and Windows/MSVC (issue 23).

## Current upstream cross-check

The current official [Goose reference](https://aardappel.github.io/goose/docs/reference.html#22-threads),
[standard library](https://aardappel.github.io/goose/docs/stdlib.html#os),
[package guide](https://aardappel.github.io/goose/docs/packages.html), and
[command-line guide](https://aardappel.github.io/goose/docs/command_line.html#3-building-an-executable)
were checked on 2026-11-23. They confirm the thread/queue model, path-based
whole-file `read_file`, `.build` C integration, and real-C-compiler requirement
for threaded programs. The online stdlib has changed since the local
v2026.4 bundle in other areas, so this note deliberately treats local docs as
the implementation target and upstream pages as a currency check only.
