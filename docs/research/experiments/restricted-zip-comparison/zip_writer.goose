// Research-only streaming writer for the restricted classic ZIP profile.
namespace zip_writer;
import std;
import os;
import gpack from "../../../../src/gpack";
import gpack.format;

let COPY_CHUNK: i64 = 1024 * 1024;
let FLAGS:      u16 = 0x0808; // UTF-8 names and a trailing data descriptor.
let DOS_DATE:   u16 = 0x0021; // 1980-01-01; DOS time is zero.

struct Source { host_path: const u8[:], asset_path: const u8[:] }
struct Directory { host_path: const u8[:], prefix: const u8[:] }
struct Entry {
    path:            const u8[:], method: u16, crc32: u32,
    compressed_size: u32, uncompressed_size: u32, local_offset: u32,
}

extern fn zip_deflate_begin(level: i32) -> u64 = "zip_deflate_begin";
extern fn zip_deflate_step(context: u64, input: const u8[:], output: u8[:], finish: bool) -> u64 = "zip_deflate_step";
extern fn zip_deflate_end(context: u64) = "zip_deflate_end";

fn put_u16(out: u8[>..]&, value: u16) {
    let bytes: u8[2] = [value as u8, (value >> 8) as u8];
    out.append(bytes);
}
fn put_u32(out: u8[>..]&, value: u32) {
    for i in 0..4 { let b: u8[1] = [(value >> (8 * i)) as u8]; out.append(b); }
}
fn write_at(handle: u64, offset: u64&, bytes: const u8[:]) -> bool {
    if offset > 0xffffffff || bytes.len as u64 > 0xffffffff - offset { return false; }
    if bytes.len > 0 && gpack::native_file_write_at(handle, offset, bytes) != bytes.len { return false; }
    offset += bytes.len as u64;
    return true;
}

fn scan_directory(dir: Directory, host_arena: u8[>..]&, path_arena: u8[>..]&, dirs: Directory[>..]&, sources: Source[>..]&) -> bool {
    var names: u8[>..] = [];
    if !list_dir(dir.host_path, names) { return false; }
    var start = 0;
    while start < names.len {
        var end = start;
        while end < names.len && names[end] != '\n' { end++; }
        let name = names[start..end];
        start = end + 1;
        if name.len == 0 { continue; }
        let host = str(dir.host_path, "/", name);
        let asset = if dir.prefix.len == 0 { str(name) } else { str(dir.prefix, "/", name) };
        let kind = gpack::native_path_kind(host);
        if kind == 2 {
            let hs = host_arena.len; host_arena.append(host);
            let ps = path_arena.len; path_arena.append(asset);
            let child: Directory[1] = [Directory { host_arena[hs..], path_arena[ps..] }];
            dirs.append(child);
        } else if kind == 1 {
            if !format::valid_path(asset) || sources.len >= 1000000 { return false; }
            let hs = host_arena.len; host_arena.append(host);
            let ps = path_arena.len; path_arena.append(asset);
            let source: Source[1] = [Source { host_arena[hs..], path_arena[ps..] }];
            sources.append(source);
        } else { return false; }
    }
    return true;
}

fn scan_tree(root: const u8[:], host_arena: u8[>..]&, path_arena: u8[>..]&, sources: Source[>..]&) -> bool {
    var dirs: Directory[>..] = [];
    dirs.push(Directory { root, "" });
    while dirs.len > 0 {
        let dir = dirs.pop();
        if !scan_directory(dir, host_arena, path_arena, dirs, sources) { return false; }
    }
    return true;
}

fn pack_one(source: Source, output: u64, offset: u64&, method: u16, entries: Entry[>..]&) -> bool {
    let input = gpack::native_file_open_read(source.host_path);
    if input == 0 { return false; }
    let size = gpack::native_file_size(input);
    let initial_stamp = gpack::native_file_stamp(input);
    if size == 0xffffffffffffffff || size > 0xffffffff || initial_stamp == 0xffffffffffffffff || offset > 0xffffffff {
        gpack::native_file_close(input); return false;
    }
    let local_offset = offset as u32;
    var local: u8[>..] = [];
    put_u32(local, 0x04034b50); put_u16(local, 20); put_u16(local, FLAGS);
    put_u16(local, method); put_u16(local, 0); put_u16(local, DOS_DATE);
    put_u32(local, 0); put_u32(local, 0); put_u32(local, 0);
    put_u16(local, source.asset_path.len as u16); put_u16(local, 0);
    local.append(source.asset_path);
    if !write_at(output, offset, local) { gpack::native_file_close(input); return false; }

    var crc_state:       u32 = 0xffffffff;
    var compressed_size: u64 = 0;
    var copied:          u64 = 0;
    var failed = false;
    var input_buffer: u8[>..] = [];
    input_buffer.resize(COPY_CHUNK, 0);
    if method == 0 {
        while copied < size && !failed {
            let count = min((size - copied) as i64, COPY_CHUNK);
            let chunk = input_buffer[..count];
            if gpack::native_file_read_at(input, copied, chunk) != count { failed = true; break; }
            crc_state = format::crc32_update(crc_state, chunk);
            if !write_at(output, offset, chunk) { failed = true; break; }
            copied += count as u64;
            compressed_size += count as u64;
        }
    } else {
        let context = zip_deflate_begin(3);
        if context == 0 { gpack::native_file_close(input); return false; }
        var output_buffer: u8[>..] = [];
        output_buffer.resize(COPY_CHUNK, 0);
        while copied < size && !failed {
            let count = min((size - copied) as i64, COPY_CHUNK);
            let chunk = input_buffer[..count];
            if gpack::native_file_read_at(input, copied, chunk) != count { failed = true; break; }
            crc_state = format::crc32_update(crc_state, chunk);
            var consumed: i64 = 0;
            while consumed < count && !failed {
                let result = zip_deflate_step(context, chunk[consumed..], output_buffer, false);
                if result == 0xffffffffffffffff { failed = true; break; }
                let used = ((result >> 32) & 0x7fffffff) as i64;
                let produced = (result & 0x7fffffff) as i64;
                if used == 0 && produced == 0 { failed = true; break; }
                if produced > 0 && !write_at(output, offset, output_buffer[..produced]) { failed = true; break; }
                consumed += used;
                compressed_size += produced as u64;
            }
            copied += count as u64;
        }
        var done = false;
        while !failed && !done {
            let result = zip_deflate_step(context, "", output_buffer, true);
            if result == 0xffffffffffffffff { failed = true; break; }
            let produced = (result & 0x7fffffff) as i64;
            done = result & 0x8000000000000000 != 0;
            if produced > 0 && !write_at(output, offset, output_buffer[..produced]) { failed = true; break; }
            compressed_size += produced as u64;
            if produced == 0 && !done { failed = true; }
        }
        zip_deflate_end(context);
    }
    let final_size = gpack::native_file_size(input);
    let final_stamp = gpack::native_file_stamp(input);
    gpack::native_file_close(input);
    if failed || final_size != size || final_stamp != initial_stamp || compressed_size > 0xffffffff { return false; }
    let crc = ~crc_state;
    var descriptor: u8[>..] = [];
    put_u32(descriptor, 0x08074b50); put_u32(descriptor, crc);
    put_u32(descriptor, compressed_size as u32); put_u32(descriptor, size as u32);
    if !write_at(output, offset, descriptor) { return false; }
    let entry: Entry[1] = [Entry { source.asset_path, method, crc, compressed_size as u32, size as u32, local_offset }];
    entries.append(entry);
    return true;
}

fn pack_directory(input_dir: const u8[:], output_path: const u8[:], method: u16) -> bool {
    if (method != 0 && method != 8) || gpack::native_path_kind(input_dir) != 2 || output_path.len == 0 { return false; }
    var host_arena: u8[>..]     = [];
    var path_arena: u8[>..]     = [];
    var sources:    Source[>..] = [];
    if !scan_tree(input_dir, host_arena, path_arena, sources) { return false; }
    stable_sort(sources) { a, b => format::path_less(a.asset_path, b.asset_path) };
    for i in 0..sources.len {
        if sources[i].host_path == output_path || (i > 0 && sources[i - 1].asset_path == sources[i].asset_path) { return false; }
    }
    var temp:   u8[>..] = [];
    var output: u64     = 0;
    for _ in 8 {
        temp.clear(); format(temp, output_path, ".zip-tmp-", gpack::native_temp_nonce());
        output = gpack::native_file_open_exclusive(temp);
        if output != 0 { break; }
    }
    if output == 0 { return false; }
    var entries: Entry[>..] = [];
    var offset:  u64        = 0;
    for source in sources {
        if !pack_one(source, output, offset, method, entries) {
            gpack::native_file_close(output); gpack::native_file_remove(temp); return false;
        }
    }
    let directory_offset = offset;
    var directory: u8[>..] = [];
    for e in entries {
        put_u32(directory, 0x02014b50); put_u16(directory, 0x0314); put_u16(directory, 20);
        put_u16(directory, FLAGS); put_u16(directory, e.method); put_u16(directory, 0); put_u16(directory, DOS_DATE);
        put_u32(directory, e.crc32); put_u32(directory, e.compressed_size); put_u32(directory, e.uncompressed_size);
        put_u16(directory, e.path.len as u16); put_u16(directory, 0); put_u16(directory, 0);
        put_u16(directory, 0); put_u16(directory, 0); put_u32(directory, 0x81a40000);
        put_u32(directory, e.local_offset); directory.append(e.path);
    }
    if directory.len as u64 > 0xffffffff || entries.len > 65535 || directory_offset > 0xffffffff ||
       !write_at(output, offset, directory) { gpack::native_file_close(output); gpack::native_file_remove(temp); return false; }
    var end: u8[22] = [0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0, 0, 0, 0, 0,
                       0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    end[8] = entries.len as u8; end[9] = (entries.len >> 8) as u8;
    end[10] = entries.len as u8; end[11] = (entries.len >> 8) as u8;
    for i in 0..4 { end[12 + i] = (directory.len as u32 >> (8 * i)) as u8; end[16 + i] = (directory_offset >> (8 * i)) as u8; }
    if !write_at(output, offset, end) || gpack::native_file_flush(output) == 0 {
        gpack::native_file_close(output); gpack::native_file_remove(temp); return false;
    }
    gpack::native_file_close(output);
    if gpack::native_file_replace(temp, output_path) == 0 { gpack::native_file_remove(temp); return false; }
    return true;
}
