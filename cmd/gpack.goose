import gpack from "../src/gpack";
import gpack.format;
import gpack.pack;
import gpack.reader;
import json;
import os;
import std;

fn write_err(msg: const u8[:]) {
    write_stderr("gpack: ");
    write_stderr(msg);
    write_stderr("\n");
}

fn usage_err(msg: const u8[:]) -> i32 {
    write_err(msg);
    write_stderr("Run 'gpack --help' for usage.\n");
    return 2;
}

fn append_pad_right(out: u8[>..]&, text: const u8[:], width: i64) {
    out.append(text);
    for _ in text.len..width { out.push(' '); }
}

fn append_pad_left(out: u8[>..]&, text: const u8[:], width: i64) {
    for _ in text.len..width { out.push(' '); }
    out.append(text);
}

fn append_hex_u32(out: u8[>..]&, value: u32) {
    out.append("0x");
    format_uint(out, value, 16, 8, '0');
}

fn append_ratio(out: u8[>..]&, stored: u64, uncompressed: u64) {
    if uncompressed == 0 {
        out.append("100.0%");
        return;
    }
    let pct = (stored * 100.0) / uncompressed;
    format_flt(out, pct, 1);
    out.push('%');
}

fn parse_size(text: const u8[:]) -> u64, bool {
    if text.len == 0 { return 0, false; }
    var split_at = text.len;
    for i in 0..text.len {
        if text[i] < '0' || text[i] > '9' { split_at = i; break; }
    }
    if split_at == 0 { return 0, false; }
    let base, ok = parse_uint(text[..split_at], 10);
    if !ok { return 0, false; }
    let suffix = text[split_at..];
    var mult: u64 = 1;
    if suffix.len == 0 || suffix == "B" || suffix == "b" {
        mult = 1;
    } else if suffix == "K" || suffix == "k" || suffix == "KiB" || suffix == "kib" {
        mult = 1024;
    } else if suffix == "KB" || suffix == "kb" {
        mult = 1000;
    } else if suffix == "M" || suffix == "m" || suffix == "MiB" || suffix == "mib" {
        mult = 1024 * 1024;
    } else if suffix == "MB" || suffix == "mb" {
        mult = 1000 * 1000;
    } else if suffix == "G" || suffix == "g" || suffix == "GiB" || suffix == "gib" {
        mult = 1024 * 1024 * 1024;
    } else if suffix == "GB" || suffix == "gb" {
        mult = 1000 * 1000 * 1000;
    } else {
        return 0, false;
    }
    if base > format::MAX_ASSET_SIZE / mult { return 0, false; }
    return base * mult, true;
}

fn parse_opt_value(arguments: u8[:][:], index: i64&, short_flag: const u8[:], long_flag: const u8[:], out: u8[>..]&) -> i32 {
    out.clear();
    let arg = arguments[index];
    let long_prefix = str(long_flag, "=");
    let short_prefix = str(short_flag, "=");
    if starts_with(arg, long_prefix) {
        let rest = arg[long_prefix.len..];
        if rest.len == 0 { return -1; }
        out.append(rest);
        return 1;
    }
    if starts_with(arg, short_prefix) {
        let rest = arg[short_prefix.len..];
        if rest.len == 0 { return -1; }
        out.append(rest);
        return 1;
    }
    if arg == long_flag || arg == short_flag {
        if index + 1 >= arguments.len { return -1; }
        index += 1;
        out.append(arguments[index]);
        return 1;
    }
    return 0;
}

fn print_version() {
    let zv = gpack::zstd_version();
    var out: u8[>..] = [];
    format(out, "gpack ", gpack::VERSION, " (format v", gpack::FORMAT_MAJOR, ".", gpack::FORMAT_MINOR,
           ", zstd ", zv / 10000, ".", (zv / 100) % 100, ".", zv % 100, ")\n");
    write_stdout(out);
}

fn print_main_help() {
    write_stdout(
        "gpack - deterministic Goose asset archive tool (format v1)\n\n",
    );
    write_stdout("Usage:\n  gpack <command> [options] [args...]\n\n");
    write_stdout("Commands:\n");
    write_stdout("  pack      Pack a directory tree into a deterministic .gpk archive\n");
    write_stdout("  list      List archive entries (alias: ls)\n");
    write_stdout("  info      Inspect archive header and summary metadata\n");
    write_stdout("  verify    Verify header, index, Zstandard frames, and CRC32 checksums\n");
    write_stdout("  read      Read a single asset to stdout by canonical path (alias: cat)\n");
    write_stdout("  version   Print version information\n");
    write_stdout("  help      Show help for a command\n\n");
    write_stdout("Global Options:\n");
    write_stdout("  -h, --help      Show help\n");
    write_stdout("  -V, --version   Print version information\n\n");
    write_stdout("Run 'gpack help <command>' for command-specific options.\n");
}

fn print_command_help(cmd: const u8[:]) -> bool {
    if cmd == "pack" {
        write_stdout("Usage: gpack pack [options] INPUT_DIR OUTPUT.gpk\n\n");
        write_stdout("Recursively pack regular files in INPUT_DIR into OUTPUT.gpk.\n");
        write_stdout("Rejects symlinks, non-regular entries, unsafe paths, and source mutations.\n\n");
        write_stdout("Options:\n");
        write_stdout("  -v, --verbose   Print pack summary after completion\n");
        write_stdout("  -q, --quiet     Suppress non-error output (default)\n");
        write_stdout("      --json      Print pack summary as JSON\n");
        write_stdout("  -h, --help      Show this help\n");
        return true;
    }
    if cmd == "list" || cmd == "ls" {
        write_stdout("Usage: gpack list [options] ARCHIVE.gpk\n\n");
        write_stdout("Validate header and index, then print archive entries without decoding payloads.\n");
        write_stdout("Default output emits '<path> <stored_size> <uncompressed_size>' per line.\n\n");
        write_stdout("Options:\n");
        write_stdout("  -l, --long      Print formatted table with codec, ratio, CRC32, and totals\n");
        write_stdout("      --json      Print entries and metadata as JSON\n");
        write_stdout("  -h, --help      Show this help\n");
        return true;
    }
    if cmd == "info" {
        write_stdout("Usage: gpack info [options] ARCHIVE.gpk\n\n");
        write_stdout("Validate header and index and print archive summary metadata.\n\n");
        write_stdout("Options:\n");
        write_stdout("      --json      Print archive metadata as JSON\n");
        write_stdout("  -h, --help      Show this help\n");
        return true;
    }
    if cmd == "verify" {
        write_stdout("Usage: gpack verify [options] ARCHIVE.gpk\n\n");
        write_stdout("Validate metadata and decode every asset, checking Zstandard frames and CRC32.\n\n");
        write_stdout("Options:\n");
        write_stdout("  -m, --max-size SIZE   Per-asset uncompressed limit (e.g. 32M, 1G; default: 32M)\n");
        write_stdout("  -j, --jobs N          Concurrent reader workers, 1..16 (default: 4)\n");
        write_stdout("  -v, --verbose         Print verification summary on success\n");
        write_stdout("  -q, --quiet           Suppress non-error output (default)\n");
        write_stdout("      --json            Print verification result as JSON\n");
        write_stdout("  -h, --help            Show this help\n");
        return true;
    }
    if cmd == "read" || cmd == "cat" {
        write_stdout("Usage: gpack read [options] ARCHIVE.gpk ASSET_PATH\n\n");
        write_stdout("Read and verify a single asset by canonical path and write its bytes to stdout.\n\n");
        write_stdout("Options:\n");
        write_stdout("  -m, --max-size SIZE   Per-asset uncompressed limit (e.g. 32M, 1G; default: 32M)\n");
        write_stdout("  -h, --help            Show this help\n");
        return true;
    }
    if cmd == "version" {
        write_stdout("Usage: gpack version\n\nPrint version information.\n");
        return true;
    }
    if cmd == "help" {
        write_stdout("Usage: gpack help [COMMAND]\n\nShow help for gpack or a subcommand.\n");
        return true;
    }
    return false;
}

fn cmd_pack(arguments: u8[:][:]) -> i32 {
    var verbose = false;
    var as_json = false;
    var end_opts = false;
    var pos: u8[:][>..] = [];
    for i in 2..arguments.len {
        let arg = arguments[i];
        if !end_opts && arg == "--" { end_opts = true; continue; }
        if !end_opts && (arg == "-h" || arg == "--help") { print_command_help("pack"); return 0; }
        if !end_opts && (arg == "-v" || arg == "--verbose") { verbose = true; continue; }
        if !end_opts && (arg == "-q" || arg == "--quiet") { verbose = false; continue; }
        if !end_opts && arg == "--json" { as_json = true; continue; }
        if !end_opts && arg.len > 1 && arg[0] == '-' {
            return usage_err(str("unknown option for pack: ", arg));
        }
        pos.push(arg);
    }
    if pos.len != 2 { return usage_err("pack requires INPUT_DIR and OUTPUT.gpk"); }

    var summary = pack::PackSummary { 0, 0, 0, 0, 0, 0, 0 };
    var error: u8[>..] = [];
    if !pack::pack_directory_detailed(pos[0], pos[1], summary, error) {
        if error.len == 0 { write_err("pack failed"); }
        else { write_err(error); }
        return 1;
    }
    if as_json {
        var out: u8[>..] = [];
        out.append("{");
        json::format_key(out, "ok"); json::format_bool(out, true); out.push(',');
        json::format_key(out, "input"); json::format_string(out, pos[0]); out.push(',');
        json::format_key(out, "output"); json::format_string(out, pos[1]); out.push(',');
        json::format_key(out, "entry_count"); format(out, summary.entry_count); out.push(',');
        json::format_key(out, "zstd_count"); format(out, summary.zstd_count); out.push(',');
        json::format_key(out, "raw_count"); format(out, summary.raw_count); out.push(',');
        json::format_key(out, "empty_count"); format(out, summary.empty_count); out.push(',');
        json::format_key(out, "uncompressed_bytes"); format(out, summary.uncompressed_bytes); out.push(',');
        json::format_key(out, "stored_bytes"); format(out, summary.stored_bytes); out.push(',');
        json::format_key(out, "archive_bytes"); format(out, summary.archive_bytes);
        out.append("}\n");
        write_stdout(out);
    } else if verbose {
        var out: u8[>..] = [];
        format(out, "Packed ", summary.entry_count, " assets (zstd=", summary.zstd_count,
               ", raw=", summary.raw_count, ", empty=", summary.empty_count, "), ",
               summary.uncompressed_bytes, " -> ", summary.archive_bytes, " bytes (");
        append_ratio(out, summary.archive_bytes, summary.uncompressed_bytes);
        format(out, ") -> ", pos[1], "\n");
        write_stdout(out);
    }
    return 0;
}

fn cmd_list(arguments: u8[:][:]) -> i32 {
    var long_fmt = false;
    var as_json = false;
    var end_opts = false;
    var pos: u8[:][>..] = [];
    for i in 2..arguments.len {
        let arg = arguments[i];
        if !end_opts && arg == "--" { end_opts = true; continue; }
        if !end_opts && (arg == "-h" || arg == "--help") { print_command_help("list"); return 0; }
        if !end_opts && (arg == "-l" || arg == "--long") { long_fmt = true; continue; }
        if !end_opts && arg == "--json" { as_json = true; continue; }
        if !end_opts && arg.len > 1 && arg[0] == '-' {
            return usage_err(str("unknown option for list: ", arg));
        }
        pos.push(arg);
    }
    if pos.len != 1 { return usage_err("list requires ARCHIVE.gpk"); }

    var archive = reader::Archive { .. };
    var error: u8[>..] = [];
    if !reader::open_detailed(pos[0], archive, reader::DEFAULT_MAX_ASSET_SIZE, error) {
        if error.len == 0 { write_err("cannot read or validate archive"); }
        else { write_err(error); }
        return 1;
    }

    if as_json {
        let meta = reader::info(archive);
        var out: u8[>..] = [];
        out.append("{");
        json::format_key(out, "format");
        var ver: u8[>..] = [];
        format(ver, meta.format_major, ".", meta.format_minor);
        json::format_string(out, ver); out.push(',');
        json::format_key(out, "file_size"); format(out, meta.file_size); out.push(',');
        json::format_key(out, "entry_count"); format(out, meta.entry_count); out.push(',');
        json::format_key(out, "uncompressed_bytes"); format(out, meta.uncompressed_bytes); out.push(',');
        json::format_key(out, "stored_bytes"); format(out, meta.stored_bytes); out.push(',');
        json::format_key(out, "entries"); out.push('[');
        for i in archive.entries.len {
            if i > 0 { out.push(','); }
            let entry = archive.entries[i];
            let codec_name = if entry.codec == format::ZSTD { "zstd" } else { "raw" };
            var crc_hex: u8[>..] = [];
            format_uint(crc_hex, entry.content_crc32, 16, 8, '0');
            out.push('{');
            json::format_key(out, "path"); json::format_string(out, reader::path_at(archive, i)); out.push(',');
            json::format_key(out, "codec"); json::format_string(out, codec_name); out.push(',');
            json::format_key(out, "stored_size"); format(out, entry.stored_size); out.push(',');
            json::format_key(out, "uncompressed_size"); format(out, entry.uncompressed_size); out.push(',');
            json::format_key(out, "crc32"); json::format_string(out, crc_hex);
            out.push('}');
        }
        out.append("]}\n");
        write_stdout(out);
    } else if long_fmt {
        var line: u8[>..] = [];
        write_stdout("CODEC        STORED          SIZE   RATIO  CRC32       PATH\n");
        var num: u8[>..] = [];
        for i in archive.entries.len {
            let entry = archive.entries[i];
            let codec_name = if entry.codec == format::ZSTD { "zstd" } else { "raw" };
            line.clear();
            append_pad_right(line, codec_name, 6);
            num.clear(); format(num, entry.stored_size);
            append_pad_left(line, num, 13); line.push(' ');
            num.clear(); format(num, entry.uncompressed_size);
            append_pad_left(line, num, 13); line.push(' ');
            num.clear(); append_ratio(num, entry.stored_size, entry.uncompressed_size);
            append_pad_left(line, num, 7); line.append("  ");
            append_hex_u32(line, entry.content_crc32); line.append("  ");
            line.append(reader::path_at(archive, i));
            line.push('\n');
            write_stdout(line);
        }
        let meta = reader::info(archive);
        line.clear();
        format(line, "\n", meta.entry_count, " assets, ", meta.stored_bytes, " stored / ",
               meta.uncompressed_bytes, " uncompressed bytes (");
        append_ratio(line, meta.stored_bytes, meta.uncompressed_bytes);
        line.append(")\n");
        write_stdout(line);
    } else {
        var line: u8[>..] = [];
        for i in archive.entries.len {
            let entry = archive.entries[i];
            format(line, reader::path_at(archive, i), " ", entry.stored_size, " ", entry.uncompressed_size, "\n");
            write_stdout(line);
            line.clear();
        }
    }
    reader::close(archive);
    return 0;
}

fn cmd_info(arguments: u8[:][:]) -> i32 {
    var as_json = false;
    var end_opts = false;
    var pos: u8[:][>..] = [];
    for i in 2..arguments.len {
        let arg = arguments[i];
        if !end_opts && arg == "--" { end_opts = true; continue; }
        if !end_opts && (arg == "-h" || arg == "--help") { print_command_help("info"); return 0; }
        if !end_opts && arg == "--json" { as_json = true; continue; }
        if !end_opts && arg.len > 1 && arg[0] == '-' {
            return usage_err(str("unknown option for info: ", arg));
        }
        pos.push(arg);
    }
    if pos.len != 1 { return usage_err("info requires ARCHIVE.gpk"); }

    var archive = reader::Archive { .. };
    var error: u8[>..] = [];
    if !reader::open_detailed(pos[0], archive, reader::DEFAULT_MAX_ASSET_SIZE, error) {
        if error.len == 0 { write_err("cannot read or validate archive"); }
        else { write_err(error); }
        return 1;
    }
    let meta = reader::info(archive);
    reader::close(archive);

    var out:     u8[>..] = [];
    var idx_crc: u8[>..] = [];
    format_uint(idx_crc, meta.index_crc32, 16, 8, '0');
    if as_json {
        var ver: u8[>..] = [];
        format(ver, meta.format_major, ".", meta.format_minor);
        out.append("{");
        json::format_key(out, "archive"); json::format_string(out, pos[0]); out.push(',');
        json::format_key(out, "format"); json::format_string(out, ver); out.push(',');
        json::format_key(out, "file_size"); format(out, meta.file_size); out.push(',');
        json::format_key(out, "entry_count"); format(out, meta.entry_count); out.push(',');
        json::format_key(out, "zstd_count"); format(out, meta.zstd_count); out.push(',');
        json::format_key(out, "raw_count"); format(out, meta.raw_count); out.push(',');
        json::format_key(out, "empty_count"); format(out, meta.empty_count); out.push(',');
        json::format_key(out, "index_offset"); format(out, meta.index_offset); out.push(',');
        json::format_key(out, "index_size"); format(out, meta.index_size); out.push(',');
        json::format_key(out, "index_crc32"); json::format_string(out, idx_crc); out.push(',');
        json::format_key(out, "uncompressed_bytes"); format(out, meta.uncompressed_bytes); out.push(',');
        json::format_key(out, "stored_bytes"); format(out, meta.stored_bytes);
        out.append("}\n");
    } else {
        format(out, "Archive:      ", pos[0], "\n");
        format(out, "Format:       gpack v", meta.format_major, ".", meta.format_minor, "\n");
        format(out, "File size:    ", meta.file_size, " bytes\n");
        format(out, "Entries:      ", meta.entry_count, " (zstd=", meta.zstd_count,
               ", raw=", meta.raw_count, ", empty=", meta.empty_count, ")\n");
        format(out, "Index:        offset ", meta.index_offset, ", ", meta.index_size, " bytes, crc32 0x", idx_crc, "\n");
        format(out, "Payloads:     ", meta.stored_bytes, " stored / ", meta.uncompressed_bytes, " uncompressed bytes (");
        append_ratio(out, meta.stored_bytes, meta.uncompressed_bytes);
        out.append(")\n");
    }
    write_stdout(out);
    return 0;
}

fn cmd_verify(arguments: u8[:][:]) -> i32 {
    var max_size = reader::DEFAULT_MAX_ASSET_SIZE;
    var jobs: i64 = 4;
    var verbose = false;
    var as_json = false;
    var end_opts = false;
    var pos: u8[:][>..] = [];
    var val: u8[>..]    = [];
    var i:   i64        = 2;
    while i < arguments.len {
        let arg = arguments[i];
        if !end_opts && arg == "--" { end_opts = true; i += 1; continue; }
        if !end_opts && (arg == "-h" || arg == "--help") { print_command_help("verify"); return 0; }
        if !end_opts && (arg == "-v" || arg == "--verbose") { verbose = true; i += 1; continue; }
        if !end_opts && (arg == "-q" || arg == "--quiet") { verbose = false; i += 1; continue; }
        if !end_opts && arg == "--json" { as_json = true; i += 1; continue; }
        if !end_opts {
            let max_rc = parse_opt_value(arguments, i, "-m", "--max-size", val);
            if max_rc < 0 { return usage_err(str("missing value for option: ", arg)); }
            if max_rc > 0 {
                let parsed, ok = parse_size(val);
                if !ok { return usage_err(str("invalid --max-size value: ", val)); }
                max_size = parsed;
                i += 1;
                continue;
            }
            let jobs_rc = parse_opt_value(arguments, i, "-j", "--jobs", val);
            if jobs_rc < 0 { return usage_err(str("missing value for option: ", arg)); }
            if jobs_rc > 0 {
                let parsed, ok = parse_int(val, 10);
                if !ok || parsed < 1 || parsed > 16 { return usage_err(str("invalid --jobs value (expected 1..16): ", val)); }
                jobs = parsed;
                i += 1;
                continue;
            }
            if arg.len > 1 && arg[0] == '-' {
                return usage_err(str("unknown option for verify: ", arg));
            }
        }
        pos.push(arg);
        i += 1;
    }
    if pos.len != 1 { return usage_err("verify requires ARCHIVE.gpk"); }

    var verified_count: u64     = 0;
    var total_bytes:    u64     = 0;
    var failed_path:    u8[>..] = [];
    var error:          u8[>..] = [];
    let ok = reader::verify_detailed(pos[0], jobs, max_size, verified_count, total_bytes, failed_path, error);
    if !ok {
        if as_json {
            var out: u8[>..] = [];
            out.append("{");
            json::format_key(out, "ok"); json::format_bool(out, false); out.push(',');
            json::format_key(out, "archive"); json::format_string(out, pos[0]); out.push(',');
            if failed_path.len > 0 {
                json::format_key(out, "failed_path"); json::format_string(out, failed_path); out.push(',');
            }
            json::format_key(out, "error");
            json::format_string(out, if error.len > 0 { error } else { "verification failed" });
            out.append("}\n");
            write_stdout(out);
        } else {
            var msg: u8[>..] = [];
            if failed_path.len > 0 {
                format(msg, "verification failed at '", failed_path, "': ", error);
            } else if error.len > 0 {
                format(msg, "verification failed: ", error);
            } else {
                msg.append("verification failed");
            }
            write_err(msg);
        }
        return 1;
    }

    if as_json {
        var out: u8[>..] = [];
        out.append("{");
        json::format_key(out, "ok"); json::format_bool(out, true); out.push(',');
        json::format_key(out, "archive"); json::format_string(out, pos[0]); out.push(',');
        json::format_key(out, "verified_entries"); format(out, verified_count); out.push(',');
        json::format_key(out, "uncompressed_bytes"); format(out, total_bytes);
        out.append("}\n");
        write_stdout(out);
    } else if verbose {
        var out: u8[>..] = [];
        format(out, "Verified ", verified_count, " assets (", total_bytes, " bytes) in ", pos[0], "\n");
        write_stdout(out);
    }
    return 0;
}

fn cmd_read(arguments: u8[:][:]) -> i32 {
    var max_size = reader::DEFAULT_MAX_ASSET_SIZE;
    var end_opts = false;
    var pos: u8[:][>..] = [];
    var val: u8[>..]    = [];
    var i:   i64        = 2;
    while i < arguments.len {
        let arg = arguments[i];
        if !end_opts && arg == "--" { end_opts = true; i += 1; continue; }
        if !end_opts && (arg == "-h" || arg == "--help") { print_command_help("read"); return 0; }
        if !end_opts {
            let max_rc = parse_opt_value(arguments, i, "-m", "--max-size", val);
            if max_rc < 0 { return usage_err(str("missing value for option: ", arg)); }
            if max_rc > 0 {
                let parsed, ok = parse_size(val);
                if !ok { return usage_err(str("invalid --max-size value: ", val)); }
                max_size = parsed;
                i += 1;
                continue;
            }
            if arg.len > 1 && arg[0] == '-' {
                return usage_err(str("unknown option for read: ", arg));
            }
        }
        pos.push(arg);
        i += 1;
    }
    if pos.len != 2 { return usage_err("read requires ARCHIVE.gpk and ASSET_PATH"); }
    if !format::valid_path(pos[1]) {
        write_err(str("invalid canonical asset path: ", pos[1]));
        return 1;
    }

    var archive = reader::Archive { .. };
    var error: u8[>..] = [];
    if !reader::open_detailed(pos[0], archive, max_size, error) {
        if error.len == 0 { write_err("cannot read or validate archive"); }
        else { write_err(error); }
        return 1;
    }
    let idx = reader::find(archive, pos[1]);
    if idx < 0 {
        reader::close(archive);
        write_err(str("asset not found: ", pos[1]));
        return 1;
    }
    let entry = archive.entries[idx];
    if entry.uncompressed_size > archive.max_asset_size {
        reader::close(archive);
        write_err(str("asset exceeds configured max size: ", pos[1]));
        return 1;
    }
    var bytes: u8[>..] = [];
    if !reader::read(archive, pos[1], bytes) {
        reader::close(archive);
        write_err(str("payload decode or CRC32/frame verification failed for: ", pos[1]));
        return 1;
    }
    reader::close(archive);
    if gpack::native_write_stdout(bytes) == 0 {
        write_err("failed writing asset bytes to stdout");
        return 1;
    }
    return 0;
}

fn main() {
    let arguments = args();
    if arguments.len <= 1 {
        print_main_help();
        exit(2);
    }
    let cmd = arguments[1];
    if cmd == "-h" || cmd == "--help" {
        print_main_help();
        return;
    }
    if cmd == "-V" || cmd == "--version" || cmd == "version" {
        if arguments.len > 2 && (arguments[2] == "-h" || arguments[2] == "--help") {
            print_command_help("version");
            return;
        }
        if arguments.len > 2 { exit(usage_err("version takes no positional arguments")); }
        print_version();
        return;
    }
    if cmd == "help" {
        if arguments.len == 2 {
            print_main_help();
            return;
        }
        if arguments.len == 3 && print_command_help(arguments[2]) {
            return;
        }
        exit(usage_err(str("unknown help topic: ", arguments[2])));
    }
    if cmd == "pack" { exit(cmd_pack(arguments)); }
    if cmd == "list" || cmd == "ls" { exit(cmd_list(arguments)); }
    if cmd == "info" { exit(cmd_info(arguments)); }
    if cmd == "verify" { exit(cmd_verify(arguments)); }
    if cmd == "read" || cmd == "cat" { exit(cmd_read(arguments)); }
    exit(usage_err(str("unknown command: ", cmd)));
}
