// Research-only reader for the preregistered single-disk ZIP profile.
namespace zip_reader;
import std;
import gpack from "../../../../src/gpack";
import gpack.format;
import gpack.format;

let MAX_ENTRIES:       u64 = 1000000;
let MAX_DIRECTORY:     u64 = 64 * 1024 * 1024;
let DEFAULT_MAX_ASSET: u64 = 32 * 1024 * 1024;
let INPUT_CHUNK:       i64 = 1024 * 1024;

struct Entry {
    path_start:      i64, path_len: i64, method: u16, crc32: u32,
    compressed_size: u64, uncompressed_size: u64,
    local_offset:    u64, payload_offset: u64,
}
struct PhysicalRange { start: u64, end: u64 }
struct ReadRequest {
    handle:            u64, method: u16, crc32: u32, compressed_size: u64,
    uncompressed_size: u64, payload_offset: u64, ticket: u64,
}
struct ReadResult { ticket: u64, ok: bool, bytes: u8[] }

root struct Archive {
    handle:         u64        = 0,
    file_size:      u64        = 0,
    max_asset_size: u64        = DEFAULT_MAX_ASSET,
    path_bytes:     u8[>..]    = [],
    entries:        Entry[>..] = [],
}

extern fn zip_inflate_begin() -> u64 = "zip_inflate_begin";
extern fn zip_inflate_step(context: u64, input: const u8[:], output: u8[:]) -> u64 = "zip_inflate_step";
extern fn zip_inflate_end(context: u64) = "zip_inflate_end";

fn read_u16(data: const u8[:], at: i64) -> u16 {
    return data[at] as u16 | (data[at + 1] as u16 << 8);
}
fn read_u32(data: const u8[:], at: i64) -> u32 {
    var value: u32 = 0;
    for i in 0..4 { value = value | (data[at + i] as u32 << (i * 8)); }
    return value;
}

fn close(archive: Archive&) {
    if archive.handle != 0 { gpack::native_file_close(archive.handle); }
    archive.handle = 0;
    archive.file_size = 0;
    archive.max_asset_size = DEFAULT_MAX_ASSET;
    archive.path_bytes.clear();
    archive.entries.clear();
}

fn open(path: const u8[:], archive: Archive&, max_asset_size: u64 = DEFAULT_MAX_ASSET) -> bool {
    if archive.handle != 0 || archive.entries.len != 0 || archive.path_bytes.len != 0 { return false; }
    let handle = gpack::native_file_open_read(path);
    if handle == 0 { return false; }
    let file_size = gpack::native_file_size(handle);
    if file_size < 22 || file_size == 0xffffffffffffffff { gpack::native_file_close(handle); return false; }

    let tail_size = min(file_size, 65557) as i64;
    var tail: u8[>..] = [];
    tail.resize(tail_size, 0);
    let tail_offset = file_size - tail_size as u64;
    if gpack::native_file_read_at(handle, tail_offset, tail) != tail_size {
        gpack::native_file_close(handle); return false;
    }
    var eocd = -1;
    var scan = tail.len - 22;
    while scan >= 0 && eocd < 0 {
        if read_u32(tail, scan) == 0x06054b50 && read_u16(tail, scan + 20) == 0 && scan + 22 == tail.len { eocd = scan; }
        scan--;
    }
    if eocd < 0 { gpack::native_file_close(handle); return false; }
    if read_u16(tail, eocd + 4) != 0 || read_u16(tail, eocd + 6) != 0 ||
       read_u16(tail, eocd + 8) != read_u16(tail, eocd + 10) { gpack::native_file_close(handle); return false; }
    let count = read_u16(tail, eocd + 10) as u64;
    let directory_size = read_u32(tail, eocd + 12) as u64;
    let directory_offset = read_u32(tail, eocd + 16) as u64;
    let eocd_offset = tail_offset + eocd as u64;
    if count > MAX_ENTRIES || directory_size > MAX_DIRECTORY || directory_size > eocd_offset ||
       directory_offset != eocd_offset - directory_size { gpack::native_file_close(handle); return false; }

    var directory: u8[>..] = [];
    directory.resize(directory_size as i64, 0);
    if directory_size > 0 && gpack::native_file_read_at(handle, directory_offset, directory) != directory_size as i64 {
        gpack::native_file_close(handle); return false;
    }
    var parsed: Entry[>..]         = [];
    var paths:  u8[>..]            = [];
    var ranges: PhysicalRange[>..] = [];
    var at:     i64                = 0;
    for _ in 0..count {
        if at > directory.len || directory.len - at < 46 || read_u32(directory, at) != 0x02014b50 {
            parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false;
        }
        let needed = read_u16(directory, at + 6);
        let flags = read_u16(directory, at + 8);
        let method = read_u16(directory, at + 10);
        let crc = read_u32(directory, at + 16);
        let compressed = read_u32(directory, at + 20) as u64;
        let uncompressed = read_u32(directory, at + 24) as u64;
        let name_len = read_u16(directory, at + 28) as i64;
        let extra_len = read_u16(directory, at + 30) as i64;
        let comment_len = read_u16(directory, at + 32) as i64;
        let disk = read_u16(directory, at + 34);
        let local_offset = read_u32(directory, at + 42) as u64;
        if needed > 20 || flags != 0x0808 || (method != 0 && method != 8) ||
           name_len == 0 || name_len > 4096 || extra_len != 0 || comment_len != 0 || disk != 0 ||
           compressed == 0xffffffff || uncompressed == 0xffffffff || local_offset == 0xffffffff ||
           uncompressed > 8 * 1024 * 1024 * 1024 || local_offset >= directory_offset ||
           at + 46 + name_len + extra_len + comment_len > directory.len {
            parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false;
        }
        let name = directory[at + 46..at + 46 + name_len];
        if !format::valid_path(name) || name[name.len - 1] == '/' ||
           (parsed.len > 0 && !format::path_less(paths[parsed[parsed.len - 1].path_start..parsed[parsed.len - 1].path_start + parsed[parsed.len - 1].path_len], name)) {
            parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false;
        }
        let local_end = local_offset + 30 + name_len as u64;
        if local_end > directory_offset { parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false; }
        var local: u8[>..] = [];
        local.resize(30 + name_len, 0);
        if gpack::native_file_read_at(handle, local_offset, local) != local.len ||
           read_u32(local, 0) != 0x04034b50 || read_u16(local, 6) != flags || read_u16(local, 8) != method ||
           read_u32(local, 14) != 0 || read_u32(local, 18) != 0 || read_u32(local, 22) != 0 ||
           read_u16(local, 26) != name_len as u16 || read_u16(local, 28) != 0 || local[30..] != name {
            parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false;
        }
        let payload = local_end;
        if payload > directory_offset || compressed > directory_offset - payload ||
           directory_offset - payload - compressed < 16 || (method == 0 && compressed != uncompressed) {
            parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false;
        }
        var descriptor: u8[16] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        let descriptor_offset = payload + compressed;
        if gpack::native_file_read_at(handle, descriptor_offset, descriptor) != descriptor.len ||
           read_u32(descriptor, 0) != 0x08074b50 || read_u32(descriptor, 4) != crc ||
           read_u32(descriptor, 8) as u64 != compressed || read_u32(descriptor, 12) as u64 != uncompressed {
            parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false;
        }
        let path_start = paths.len;
        paths.append(name);
        let row: Entry[1] = [Entry { path_start, name_len, method, crc, compressed, uncompressed, local_offset, payload }];
        parsed.append(row);
        let physical: PhysicalRange[1] = [PhysicalRange { local_offset, descriptor_offset + 16 }];
        ranges.append(physical);
        at += 46 + name_len;
    }
    if at != directory.len { parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false; }
    stable_sort(ranges) { a, b => a.start < b.start };
    var end: u64 = 0;
    for range in ranges {
        if range.start != end || range.end < range.start { parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false; }
        end = range.end;
    }
    if end != directory_offset { parsed.clear(); paths.clear(); ranges.clear(); gpack::native_file_close(handle); return false; }
    archive.handle = handle;
    archive.file_size = file_size;
    archive.max_asset_size = max_asset_size;
    archive.entries = copy(parsed);
    archive.path_bytes = copy(paths);
    return true;
}

fn path_at(archive: Archive&, index: i64) -> const u8[:] {
    if index < 0 || index >= archive.entries.len { return archive.path_bytes[..0]; }
    let e = archive.entries[index];
    return archive.path_bytes[e.path_start..e.path_start + e.path_len];
}

fn find(archive: Archive&, path: const u8[:]) -> i64 {
    if !format::valid_path(path) { return -1; }
    var lo: i64 = 0;
    var hi = archive.entries.len;
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        let e = archive.entries[mid];
        let candidate = archive.path_bytes[e.path_start..e.path_start + e.path_len];
        if candidate == path { return mid; }
        if format::path_less(candidate, path) { lo = mid + 1; } else { hi = mid; }
    }
    return -1;
}

fn request(archive: Archive&, path: const u8[:], ticket: u64 = 0) -> ReadRequest, bool {
    if archive.handle == 0 { return ReadRequest { 0, 0, 0, 0, 0, 0, 0 }, false; }
    let index = find(archive, path);
    if index < 0 { return ReadRequest { 0, 0, 0, 0, 0, 0, 0 }, false; }
    let e = archive.entries[index];
    if e.uncompressed_size > archive.max_asset_size || e.uncompressed_size > 0x7ffffffe ||
       e.compressed_size > 0x7fffffff { return ReadRequest { 0, 0, 0, 0, 0, 0, 0 }, false; }
    return ReadRequest { archive.handle, e.method, e.crc32, e.compressed_size, e.uncompressed_size, e.payload_offset, ticket }, true;
}

fn read_request(request: ReadRequest, out: u8[>..]&) -> bool {
    out.clear();
    if request.handle == 0 || request.uncompressed_size > 0x7ffffffe ||
       request.compressed_size > 0x7fffffff || (request.method != 0 && request.method != 8) { return false; }
    if request.method == 0 {
        out.resize(request.uncompressed_size as i64, 0);
        if request.uncompressed_size > 0 && gpack::native_file_read_at(request.handle, request.payload_offset, out) != out.len { out.clear(); return false; }
        return format::crc32(out) == request.crc32;
    }
    out.resize(request.uncompressed_size as i64 + 1, 0);
    let context = zip_inflate_begin();
    if context == 0 { out.clear(); return false; }
    var input: u8[>..] = [];
    input.resize(INPUT_CHUNK, 0);
    var input_offset:  u64 = 0;
    var output_offset: i64 = 0;
    var done = false;
    var failed = false;
    while input_offset < request.compressed_size && !done && !failed {
        let count = min((request.compressed_size - input_offset) as i64, INPUT_CHUNK);
        let chunk = input[..count];
        if gpack::native_file_read_at(request.handle, request.payload_offset + input_offset, chunk) != count { failed = true; break; }
        let result = zip_inflate_step(context, chunk, out[output_offset..]);
        if result == 0xffffffffffffffff { failed = true; break; }
        let consumed = ((result >> 32) & 0x7fffffff) as u64;
        let produced = (result & 0x7fffffff) as i64;
        done = result & 0x8000000000000000 != 0;
        if consumed == 0 && produced == 0 && !done { failed = true; break; }
        input_offset += consumed;
        output_offset += produced;
        if output_offset > request.uncompressed_size as i64 || (done && input_offset != request.compressed_size) { failed = true; }
    }
    zip_inflate_end(context);
    if failed || !done || input_offset != request.compressed_size || output_offset != request.uncompressed_size as i64 {
        out.clear(); return false;
    }
    out.resize(request.uncompressed_size as i64, 0);
    if format::crc32(out) != request.crc32 { out.clear(); return false; }
    return true;
}
