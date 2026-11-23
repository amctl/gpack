// Read-only archive handles. All GPack validation stays in Goose; native I/O
// uses positional reads so independent calls never share a file cursor.
namespace reader;
import std;
import gpack;
import format;

let DEFAULT_MAX_ASSET_SIZE:   u64 = 32 * 1024 * 1024;
let SMALL_FRAME_ONE_SHOT_MAX: u64 = 1024 * 1024;

struct RuntimeEntry {
    path_start:     i64, path_len: i64, codec: u8, uncompressed_size: u64,
    payload_offset: u64, stored_size: u64, content_crc32: u32,
}
struct ReadRequest { handle: u64, payload_offset: u64, size: u64, stored_size: u64, content_crc32: u32, codec: u8, ticket: u64 }
struct ReadResult { ticket: u64, ok: bool, bytes: u8[] }

root struct Archive {
    handle:         u64               = 0,
    file_size:      u64               = 0,
    max_asset_size: u64               = DEFAULT_MAX_ASSET_SIZE,
    header:         format::Header    = format::Header { 0, 0, 0, 0 },
    path_bytes:     u8[>..]           = [],
    entries:        RuntimeEntry[>..] = [],
}

fn close(archive: Archive&) {
    if archive.handle != 0 { gpack::native_file_close(archive.handle); }
    archive.handle = 0;
    archive.file_size = 0;
    archive.entries.clear();
    archive.path_bytes.clear();
    archive.header = format::Header { 0, 0, 0, 0 };
}

fn open(path: const u8[:], archive: Archive&, max_asset_size: u64 = DEFAULT_MAX_ASSET_SIZE) -> bool {
    if archive.handle != 0 || archive.entries.len != 0 || archive.path_bytes.len != 0 { return false; }
    let handle = gpack::native_file_open_read(path);
    if handle == 0 { return false; }
    let size = gpack::native_file_size(handle);
    if size == 0xffffffffffffffff || size < 68 { gpack::native_file_close(handle); return false; }

    var header_bytes: u8[>..] = [];
    header_bytes.resize(format::HEADER_SIZE, 0);
    if gpack::native_file_read_at(handle, 0, header_bytes) != format::HEADER_SIZE {
        gpack::native_file_close(handle); return false;
    }
    let header, header_ok = format::decode_header(header_bytes, size);
    if !header_ok { gpack::native_file_close(handle); return false; }
    var index_bytes: u8[>..] = [];
    index_bytes.resize(header.index_size as i64, 0);
    if gpack::native_file_read_at(handle, header.index_offset, index_bytes) != header.index_size as i64 {
        gpack::native_file_close(handle); return false;
    }
    var parsed_entries: format::Entry[>..] = [];
    if !format::decode_index(index_bytes, header, parsed_entries) {
        parsed_entries.clear();
        gpack::native_file_close(handle); return false;
    }
    for entry in parsed_entries {
        let path_start = archive.path_bytes.len;
        archive.path_bytes.append(entry.path);
        let owned: RuntimeEntry[1] = [RuntimeEntry {
            path_start, entry.path.len, entry.codec, entry.uncompressed_size,
            entry.payload_offset, entry.stored_size, entry.content_crc32,
        }];
        archive.entries.append(owned);
    }
    parsed_entries.clear();
    archive.handle = handle;
    archive.file_size = size;
    archive.max_asset_size = max_asset_size;
    archive.header = header;
    return true;
}

fn find(archive: Archive&, path: const u8[:]) -> i64 {
    if !format::valid_path(path) { return -1; }
    var lo = 0;
    var hi = archive.entries.len;
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        let entry = archive.entries[mid];
        let candidate = archive.path_bytes[entry.path_start..entry.path_start + entry.path_len];
        if candidate == path { return mid; }
        if format::path_less(candidate, path) { lo = mid + 1; }
        else { hi = mid; }
    }
    return -1;
}

fn path_at(archive: Archive&, index: i64) -> const u8[:] {
    if index < 0 || index >= archive.entries.len { return archive.path_bytes[..0]; }
    let entry = archive.entries[index];
    return archive.path_bytes[entry.path_start..entry.path_start + entry.path_len];
}

fn request(archive: Archive&, path: const u8[:], ticket: u64 = 0) -> ReadRequest, bool {
    if archive.handle == 0 { return ReadRequest { 0, 0, 0, 0, 0, 0, 0 }, false; }
    let i = find(archive, path);
    if i < 0 { return ReadRequest { 0, 0, 0, 0, 0, 0, 0 }, false; }
    let entry = archive.entries[i];
    if (entry.codec != format::RAW && entry.codec != format::ZSTD) || entry.uncompressed_size > archive.max_asset_size || entry.uncompressed_size > 0x7fffffffffffffff {
        return ReadRequest { 0, 0, 0, 0, 0, 0, 0 }, false;
    }
    return ReadRequest { archive.handle, entry.payload_offset, entry.uncompressed_size, entry.stored_size, entry.content_crc32, entry.codec, ticket }, true;
}

fn read_request(request: ReadRequest, out: u8[>..]&) -> bool {
    out.clear();
    if request.handle == 0 || request.size > 0x7fffffffffffffff || (request.codec != format::RAW && request.codec != format::ZSTD) { return false; }
    out.resize(request.size as i64, 0);
    if request.codec == format::RAW {
        if request.size != 0 && gpack::native_file_read_at(request.handle, request.payload_offset, out) != request.size as i64 {
            out.clear(); return false;
        }
    } else {
        if request.stored_size <= SMALL_FRAME_ONE_SHOT_MAX {
            var encoded: u8[>..] = [];
            encoded.resize(request.stored_size as i64, 0);
            if request.stored_size == 0 || gpack::native_file_read_at(request.handle, request.payload_offset, encoded) != request.stored_size as i64 ||
               gpack::native_zstd_decompress_one_shot(encoded, out, window_log(request.size)) == 0 {
                out.clear(); return false;
            }
            if format::crc32(out) != request.content_crc32 { out.clear(); return false; }
            return true;
        }
        let context = gpack::native_zstd_decompress_begin(window_log(request.size));
        if context == 0 { out.clear(); return false; }
        var input_buffer: u8[>..] = [];
        input_buffer.resize(1024 * 1024, 0);
        var input_offset:  u64 = 0;
        var output_offset: i64 = 0;
        var done = false;
        var failed = false;
        while input_offset < request.stored_size && !done && !failed {
            let count = min((request.stored_size - input_offset) as i64, input_buffer.len);
            let input = input_buffer[..count];
            if gpack::native_file_read_at(request.handle, request.payload_offset + input_offset, input) != count {
                failed = true; break;
            }
            let output = out[output_offset..];
            let result = gpack::native_zstd_decompress_step(context, input, output);
            if result == 0xffffffffffffffff { failed = true; break; }
            let consumed = (result >> 32) & 0x7fffffff;
            let produced = (result & 0x7fffffff) as i64;
            done = result & 0x8000000000000000 != 0;
            if consumed == 0 && produced == 0 && !done { failed = true; break; }
            input_offset += consumed;
            output_offset += produced;
            if done && input_offset != request.stored_size { failed = true; }
        }
        if !done || input_offset != request.stored_size || output_offset != request.size as i64 { failed = true; }
        gpack::native_zstd_decompress_end(context);
        if failed { out.clear(); return false; }
    }
    if format::crc32(out) != request.content_crc32 { out.clear(); return false; }
    return true;
}

fn window_log(size: u64) -> i32 {
    var power: u64 = 1;
    var log:   i32 = 0;
    while power < size && log < 31 { power <<= 1; log++; }
    return max(10, log);
}

// A flat request can cross Goose's typed worker queues, so four workers can
// read one open handle concurrently without sharing mutable Goose state. The
// caller should allow four results in its ReadResult queue and drain it.
thread_fn read_worker(request: ReadRequest) {
    var bytes: u8[>..] = [];
    let ok = read_request(request, bytes);
    assert(qput(ReadResult { request.ticket, ok, copy(bytes) }));
}

// Reads one complete raw asset into out. Separate output builders can be used
// concurrently with the same archive because the native operation is pread/
// overlapped I/O and the validated index is immutable after open.
fn read(archive: Archive&, path: const u8[:], out: u8[>..]&) -> bool {
    out.clear();
    let request, ok = request(archive, path);
    if !ok { return false; }
    return read_request(request, out);
}

fn list(path: const u8[:]) -> bool {
    var archive = Archive { .. };
    if !open(path, archive) { return false; }
    var line: u8[>..] = [];
    for i in archive.entries.len {
        let entry = archive.entries[i];
        format(line, path_at(archive, i), " ", entry.stored_size, " ", entry.uncompressed_size, "\n");
        write_stdout(line);
        line.clear();
    }
    close(archive);
    return true;
}

fn verify(path: const u8[:], max_asset_size: u64 = DEFAULT_MAX_ASSET_SIZE) -> bool {
    var archive = Archive { .. };
    if !open(path, archive, max_asset_size) { return false; }
    var bytes: u8[>..] = [];
    for i in archive.entries.len {
        if !read(archive, path_at(archive, i), bytes) { close(archive); return false; }
    }
    close(archive);
    return true;
}
