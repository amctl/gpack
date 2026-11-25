// Deterministic directory packing with sibling-temp atomic publication.
namespace pack;
import std;
import os;
import gpack;
import format;

let COPY_CHUNK: i64 = 1024 * 1024;

struct Source { host_path: const u8[:], asset_path: const u8[:] }
struct Directory { host_path: const u8[:], prefix: const u8[:] }
struct PackSummary {
    entry_count:        u64, raw_count: u64, zstd_count: u64, empty_count: u64,
    uncompressed_bytes: u64, stored_bytes: u64, archive_bytes: u64,
}

fn set_error(error: u8[>..]&, message: const u8[:]) {
    error.clear();
    error.append(message);
}

fn scan_directory(dir: Directory, host_arena: u8[>..]&, path_arena: u8[>..]&,
                  directories: Directory[>..]&, sources: Source[>..]&, error: u8[>..]&) -> bool {
    var names: u8[>..] = [];
    if !list_dir(dir.host_path, names) {
        set_error(error, "cannot read input directory");
        return false;
    }
    var start = 0;
    while start < names.len {
        var end = start;
        while end < names.len && names[end] != '\n' { end++; }
        let name = names[start..end];
        start = end + 1;
        if name.len == 0 { continue; }
        let has_sep = dir.host_path.len > 0 &&
            (dir.host_path[dir.host_path.len - 1] == '/' || dir.host_path[dir.host_path.len - 1] == '\\');
        let host = if has_sep { str(dir.host_path, name) } else { str(dir.host_path, "/", name) };
        let relative = if dir.prefix.len == 0 { str(name) } else { str(dir.prefix, "/", name) };
        let kind = gpack::native_path_kind(host);
        if kind == 2 {
            let host_start = host_arena.len;
            host_arena.append(host);
            let path_start = path_arena.len;
            path_arena.append(relative);
            let child: Directory[1] = [Directory { host_arena[host_start..], path_arena[path_start..] }];
            directories.append(child);
        } else if kind == 1 {
            if !format::valid_path(relative) {
                set_error(error, "unsafe or invalid UTF-8 asset path");
                return false;
            }
            if sources.len >= format::MAX_ENTRIES {
                set_error(error, "entry count exceeds v1 limit of 1,000,000");
                return false;
            }
            let host_start = host_arena.len;
            host_arena.append(host);
            let path_start = path_arena.len;
            path_arena.append(relative);
            let source: Source[1] = [Source { host_arena[host_start..], path_arena[path_start..] }];
            sources.append(source);
        } else {
            // Symlinks and every non-regular filesystem entry are rejected.
            set_error(error, "rejected symlink or non-regular filesystem entry");
            return false;
        }
    }
    return true;
}

fn scan_tree(root: const u8[:], host_arena: u8[>..]&, path_arena: u8[>..]&,
             sources: Source[>..]&, error: u8[>..]&) -> bool {
    var directories: Directory[>..] = [];
    directories.push(Directory { root, "" });
    while directories.len > 0 {
        let dir = directories.pop();
        if !scan_directory(dir, host_arena, path_arena, directories, sources, error) { return false; }
    }
    return true;
}

fn pack_one(source: Source, output: u64, output_offset: u64&,
            entries: format::Entry[>..]&, summary: PackSummary&, error: u8[>..]&) -> bool {
    let input = gpack::native_file_open_read(source.host_path);
    if input == 0 {
        set_error(error, "cannot open input file (missing, unreadable, or symlink)");
        return false;
    }
    let size = gpack::native_file_size(input);
    let initial_stamp = gpack::native_file_stamp(input);
    if size == 0xffffffffffffffff || initial_stamp == 0xffffffffffffffff {
        gpack::native_file_close(input);
        set_error(error, "cannot stat input file");
        return false;
    }
    if size > format::MAX_ASSET_SIZE || output_offset > 0x7fffffffffffffff - size {
        gpack::native_file_close(input);
        set_error(error, "input asset exceeds v1 8 GiB limit");
        return false;
    }
    let payload_offset = output_offset;
    var crc_state: u32 = 0;
    var stored_size = size;
    var codec = format::RAW;
    var failed = false;

    if size > 0 {
        let context = gpack::native_zstd_compress_begin(size);
        if context == 0 {
            gpack::native_file_close(input);
            set_error(error, "cannot initialize Zstandard compressor");
            return false;
        }
        var input_buffer: u8[>..] = [];
        input_buffer.resize(COPY_CHUNK, 0);
        var output_buffer:   u8[>..] = [];
        var compressed_size: u64     = 0;
        var copied:          u64     = 0;
        var fallback = false;
        crc_state = 0xffffffff;

        while copied < size && !fallback && !failed {
            let count = min((size - copied) as i64, COPY_CHUNK);
            let chunk = input_buffer[..count];
            if gpack::native_file_read_at(input, copied, chunk) != count { failed = true; break; }
            crc_state = format::crc32_update(crc_state, chunk);
            var chunk_pos: i64 = 0;
            while chunk_pos < count && !fallback && !failed {
                let room = size - compressed_size;
                if room == 0 { fallback = true; break; }
                let output_capacity = min(room as i64, COPY_CHUNK);
                output_buffer.resize(output_capacity, 0);
                let result = gpack::native_zstd_compress_step(context, chunk[chunk_pos..], output_buffer, false);
                if result == 0xffffffffffffffff { failed = true; break; }
                let consumed = ((result >> 32) & 0x7fffffff) as i64;
                let produced = (result & 0x7fffffff) as i64;
                if produced > 0 && gpack::native_file_write_at(output, payload_offset + compressed_size, output_buffer[..produced]) != produced {
                    failed = true; break;
                }
                compressed_size += produced as u64;
                chunk_pos += consumed;
                if compressed_size >= size || (consumed == 0 && produced == 0) { fallback = true; break; }
            }
            if !fallback && !failed { copied += count as u64; }
        }

        while copied == size && !fallback && !failed {
            let room = size - compressed_size;
            if room == 0 { fallback = true; break; }
            let output_capacity = min(room as i64, COPY_CHUNK);
            output_buffer.resize(output_capacity, 0);
            let result = gpack::native_zstd_compress_step(context, "", output_buffer, true);
            if result == 0xffffffffffffffff { failed = true; break; }
            let produced = (result & 0x7fffffff) as i64;
            let done = result & 0x8000000000000000 != 0;
            if produced > 0 && gpack::native_file_write_at(output, payload_offset + compressed_size, output_buffer[..produced]) != produced {
                failed = true; break;
            }
            compressed_size += produced as u64;
            if compressed_size >= size { fallback = true; break; }
            if done { break; }
            if produced == 0 { fallback = true; }
        }
        gpack::native_zstd_compress_end(context);
        if failed {
            gpack::native_file_close(input);
            set_error(error, "I/O or Zstandard compression failure while packing asset");
            return false;
        }

        if !fallback && copied == size && compressed_size < size {
            codec = format::ZSTD;
            stored_size = compressed_size;
        } else {
            fallback = true;
        }
        if fallback {
            crc_state = 0xffffffff;
            var raw_copied: u64 = 0;
            while raw_copied < size {
                let count = min((size - raw_copied) as i64, COPY_CHUNK);
                let chunk = input_buffer[..count];
                if gpack::native_file_read_at(input, raw_copied, chunk) != count { failed = true; break; }
                crc_state = format::crc32_update(crc_state, chunk);
                if gpack::native_file_write_at(output, payload_offset + raw_copied, chunk) != count { failed = true; break; }
                raw_copied += count as u64;
            }
            if failed {
                gpack::native_file_close(input);
                set_error(error, "I/O failure while writing raw asset payload");
                return false;
            }
            stored_size = size;
            output_offset = payload_offset + size;
        } else {
            output_offset = payload_offset + compressed_size;
        }
    }
    let final_size = gpack::native_file_size(input);
    let final_stamp = gpack::native_file_stamp(input);
    gpack::native_file_close(input);
    if final_size != size || final_stamp != initial_stamp {
        set_error(error, "source file changed during pack");
        return false;
    }
    let entry: format::Entry[1] = [format::Entry { source.asset_path, codec, size, payload_offset, stored_size, if size == 0 { 0 } else { ~crc_state } }];
    entries.append(entry);
    summary.entry_count += 1;
    summary.uncompressed_bytes += size;
    summary.stored_bytes += stored_size;
    if size == 0 { summary.empty_count += 1; }
    else if codec == format::ZSTD { summary.zstd_count += 1; }
    else { summary.raw_count += 1; }
    return true;
}

fn pack_directory_detailed(input_dir: const u8[:], output_path: const u8[:],
                           summary: PackSummary&, error: u8[>..]&) -> bool {
    summary = PackSummary { 0, 0, 0, 0, 0, 0, 0 };
    error.clear();
    if gpack::native_path_kind(input_dir) != 2 {
        set_error(error, "input path is not a directory");
        return false;
    }
    if output_path.len == 0 {
        set_error(error, "output path is empty");
        return false;
    }
    var host_arena: u8[>..]     = [];
    var path_arena: u8[>..]     = [];
    var sources:    Source[>..] = [];
    if !scan_tree(input_dir, host_arena, path_arena, sources, error) { return false; }
    stable_sort(sources) { a, b => format::path_less(a.asset_path, b.asset_path) };
    for i in 0..sources.len {
        if sources[i].host_path == output_path {
            set_error(error, "output path matches an input file");
            return false;
        }
        if i > 0 && sources[i - 1].asset_path == sources[i].asset_path {
            set_error(error, "duplicate canonical asset path");
            return false;
        }
    }

    var temporary_path: u8[>..] = [];
    var output:         u64     = 0;
    for _ in 8 {
        temporary_path.clear();
        format(temporary_path, output_path, ".gpack-tmp-", gpack::native_temp_nonce());
        output = gpack::native_file_open_exclusive(temporary_path);
        if output != 0 { break; }
    }
    if output == 0 {
        set_error(error, "cannot create temporary archive beside output");
        return false;
    }
    var header_placeholder: u8[>..] = [];
    header_placeholder.resize(format::HEADER_SIZE, 0);
    if gpack::native_file_write_at(output, 0, header_placeholder) != format::HEADER_SIZE {
        gpack::native_file_close(output); gpack::native_file_remove(temporary_path);
        set_error(error, "failed writing archive header placeholder");
        return false;
    }
    var entries:       format::Entry[>..] = [];
    var output_offset: u64                = format::HEADER_SIZE as u64;
    for source in sources {
        if !pack_one(source, output, output_offset, entries, summary, error) {
            gpack::native_file_close(output); gpack::native_file_remove(temporary_path); return false;
        }
    }
    let index_bytes, index_ok = format::encode_index(entries);
    if !index_ok {
        gpack::native_file_close(output); gpack::native_file_remove(temporary_path);
        set_error(error, "archive index exceeds v1 64 MiB limit");
        return false;
    }
    let index_offset = output_offset;
    if gpack::native_file_write_at(output, index_offset, index_bytes) != index_bytes.len {
        gpack::native_file_close(output); gpack::native_file_remove(temporary_path);
        set_error(error, "failed writing archive index");
        return false;
    }
    let header = format::encode_header(format::Header { entries.len as u64, index_offset, index_bytes.len as u64, format::crc32(index_bytes) });
    if gpack::native_file_write_at(output, 0, header) != header.len || gpack::native_file_flush(output) == 0 {
        gpack::native_file_close(output); gpack::native_file_remove(temporary_path);
        set_error(error, "failed writing or flushing archive header");
        return false;
    }
    gpack::native_file_close(output);
    if gpack::native_file_replace(temporary_path, output_path) == 0 {
        gpack::native_file_remove(temporary_path);
        set_error(error, "atomic replace of output archive failed");
        return false;
    }
    summary.archive_bytes = index_offset + index_bytes.len as u64;
    return true;
}

fn pack_directory(input_dir: const u8[:], output_path: const u8[:]) -> bool {
    var summary = PackSummary { 0, 0, 0, 0, 0, 0, 0 };
    var error: u8[>..] = [];
    return pack_directory_detailed(input_dir, output_path, summary, error);
}
