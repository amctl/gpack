// Research-only raw GPack writer for the container-focused ZIP arm.
namespace gpack_raw_pack;
import std;
import os;
import gpack from "../../../../src/gpack";
import gpack.format;

let CHUNK: i64 = 1024 * 1024;
struct Source { host: const u8[:], path: const u8[:] }
struct Directory { host: const u8[:], prefix: const u8[:] }

fn scan(dir: Directory, hosts: u8[>..]&, paths: u8[>..]&, dirs: Directory[>..]&, files: Source[>..]&) -> bool {
    var names: u8[>..] = [];
    if !list_dir(dir.host, names) { return false; }
    var at = 0;
    while at < names.len {
        var end = at;
        while end < names.len && names[end] != '\n' { end++; }
        let name = names[at..end]; at = end + 1;
        if name.len == 0 { continue; }
        let host = str(dir.host, "/", name);
        let path = if dir.prefix.len == 0 { str(name) } else { str(dir.prefix, "/", name) };
        let kind = gpack::native_path_kind(host);
        if kind == 2 {
            let hs = hosts.len; hosts.append(host);
            let ps = paths.len; paths.append(path);
            let child: Directory[1] = [Directory { hosts[hs..], paths[ps..] }]; dirs.append(child);
        } else if kind == 1 {
            if !format::valid_path(path) || files.len >= format::MAX_ENTRIES { return false; }
            let hs = hosts.len; hosts.append(host);
            let ps = paths.len; paths.append(path);
            let file: Source[1] = [Source { hosts[hs..], paths[ps..] }]; files.append(file);
        } else { return false; }
    }
    return true;
}

fn write_file(source: Source, output: u64, offset: u64&, entries: format::Entry[>..]&) -> bool {
    let input = gpack::native_file_open_read(source.host);
    if input == 0 { return false; }
    let size = gpack::native_file_size(input);
    let stamp = gpack::native_file_stamp(input);
    if size == 0xffffffffffffffff || size > format::MAX_ASSET_SIZE || stamp == 0xffffffffffffffff || offset > 0x7fffffffffffffff - size {
        gpack::native_file_close(input); return false;
    }
    let payload = offset;
    var crc: u32 = 0xffffffff;
    var copied: u64 = 0;
    var buffer: u8[>..] = []; buffer.resize(CHUNK, 0);
    while copied < size {
        let count = min((size - copied) as i64, CHUNK);
        let bytes = buffer[..count];
        if gpack::native_file_read_at(input, copied, bytes) != count ||
           gpack::native_file_write_at(output, offset, bytes) != count {
            gpack::native_file_close(input); return false;
        }
        crc = format::crc32_update(crc, bytes);
        copied += count as u64; offset += count as u64;
    }
    let unchanged = gpack::native_file_size(input) == size && gpack::native_file_stamp(input) == stamp;
    gpack::native_file_close(input);
    if !unchanged { return false; }
    let row: format::Entry[1] = [format::Entry { source.path, format::RAW, size, payload, size, if size == 0 { 0 } else { ~crc } }];
    entries.append(row);
    return true;
}

fn pack(input_dir: const u8[:], output_path: const u8[:]) -> bool {
    if gpack::native_path_kind(input_dir) != 2 || output_path.len == 0 { return false; }
    var hosts: u8[>..] = []; var paths: u8[>..] = [];
    var dirs: Directory[>..] = []; var files: Source[>..] = [];
    dirs.push(Directory { input_dir, "" });
    while dirs.len > 0 { if !scan(dirs.pop(), hosts, paths, dirs, files) { return false; } }
    stable_sort(files) { a, b => format::path_less(a.path, b.path) };
    for i in 0..files.len { if i > 0 && files[i - 1].path == files[i].path { return false; } }
    var temp: u8[>..] = []; var output: u64 = 0;
    for _ in 8 {
        temp.clear(); format(temp, output_path, ".gpack-raw-tmp-", gpack::native_temp_nonce());
        output = gpack::native_file_open_exclusive(temp); if output != 0 { break; }
    }
    if output == 0 { return false; }
    var placeholder: u8[>..] = []; placeholder.resize(format::HEADER_SIZE, 0);
    if gpack::native_file_write_at(output, 0, placeholder) != placeholder.len { gpack::native_file_close(output); gpack::native_file_remove(temp); return false; }
    var entries: format::Entry[>..] = []; var offset: u64 = format::HEADER_SIZE as u64;
    for file in files { if !write_file(file, output, offset, entries) { gpack::native_file_close(output); gpack::native_file_remove(temp); return false; } }
    let index, ok = format::encode_index(entries);
    if !ok || gpack::native_file_write_at(output, offset, index) != index.len { gpack::native_file_close(output); gpack::native_file_remove(temp); return false; }
    let header = format::encode_header(format::Header { entries.len as u64, offset, index.len as u64, format::crc32(index) });
    if gpack::native_file_write_at(output, 0, header) != header.len || gpack::native_file_flush(output) == 0 {
        gpack::native_file_close(output); gpack::native_file_remove(temp); return false;
    }
    gpack::native_file_close(output);
    if gpack::native_file_replace(temp, output_path) == 0 { gpack::native_file_remove(temp); return false; }
    return true;
}
