# gpack CLI Reference

```text
gpack <command> [options] [args...]
```

## Global Options

- `-h`, `--help` — display main usage or command help.
- `-V`, `--version` — print `gpack`, format, and linked Zstandard version.

## Exit Codes

| Code | Meaning |
|---:|---|
| `0` | Success |
| `1` | Archive, path, I/O, size-limit, or verification error |
| `2` | CLI usage error (unknown command/flag, missing or invalid argument) |

Use `--` before positional arguments to pass paths beginning with `-`. Commands supporting `--json` (`pack`, `list`, `info`, `verify`) emit a JSON object with `"ok":false` and `"error":"..."` to `stdout` on runtime failure (exit `1`); usage errors (exit `2`) always write to `stderr`.

## Commands

### `pack`

Recursively pack regular files in `INPUT_DIR` into `OUTPUT.gpk` atomically.

```text
gpack pack [options] INPUT_DIR OUTPUT.gpk
```

- Rejects symlinks, non-regular entries, invalid UTF-8 or unsafe paths, duplicate canonical paths, and detected source file mutations.
- Stages output in a sibling temporary file, flushes, and atomically replaces `OUTPUT.gpk` only on success.

Options:
- `-v`, `--verbose` — print entry counts, compression summary, and output path.
- `-q`, `--quiet` — suppress non-error output (default).
- `--json` — print summary JSON (`ok`, `input`, `output`, `entry_count`, `zstd_count`, `raw_count`, `empty_count`, `uncompressed_bytes`, `stored_bytes`, `archive_bytes`).
- `-h`, `--help` — show `pack` help.

### `list` (alias: `ls`)

Validate the header and complete index without decoding payloads, then list entries.

```text
gpack list [options] ARCHIVE.gpk
```

- Default output prints `<path> <stored_size> <uncompressed_size>` per line.

Options:
- `-l`, `--long` — print a formatted table (`CODEC`, `STORED`, `SIZE`, `RATIO`, `CRC32`, `PATH`) and totals footer.
- `--json` — print JSON object containing `format`, `file_size`, `entry_count`, `uncompressed_bytes`, `stored_bytes`, and `entries[]`.
- `-h`, `--help` — show `list` help.

### `info`

Validate metadata and print archive summary without decoding payloads.

```text
gpack info [options] ARCHIVE.gpk
```

Options:
- `--json` — print JSON object (`archive`, `format`, `file_size`, `entry_count`, `zstd_count`, `raw_count`, `empty_count`, `index_offset`, `index_size`, `index_crc32`, `uncompressed_bytes`, `stored_bytes`).
- `-h`, `--help` — show `info` help.

### `verify`

Validate metadata and decode every asset in `ARCHIVE.gpk`, verifying Zstandard frames and IEEE CRC32 checksums.

```text
gpack verify [options] ARCHIVE.gpk
```

Options:
- `-m`, `--max-size SIZE` — maximum uncompressed asset size allowed (default `32M`, up to `8G`). Accepts integer bytes or suffixes `B`, `K`/`KiB` (1024), `KB` (1000), `M`/`MiB`, `MB`, `G`/`GiB`, `GB`.
- `-j`, `--jobs N` — concurrent reader workers, `1..16` (default `4`).
- `-v`, `--verbose` — print verified asset count and byte total on success.
- `-q`, `--quiet` — suppress non-error output (default).
- `--json` — print verification result JSON (`ok`, `archive`, `verified_entries`, `uncompressed_bytes`, or `ok`, `archive`, optional `failed_path`, and `error` on failure).
- `-h`, `--help` — show `verify` help.

### `read` (alias: `cat`)

Read and verify a single asset by canonical path and write its exact bytes to `stdout` without extracting to the filesystem.

```text
gpack read [options] ARCHIVE.gpk ASSET_PATH
```

Options:
- `-m`, `--max-size SIZE` — maximum uncompressed asset size allowed (default `32M`).
- `-h`, `--help` — show `read` help.

### `version` & `help`

```text
gpack version
gpack help [COMMAND]
```
