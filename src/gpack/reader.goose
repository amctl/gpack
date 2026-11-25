// Read-only archive handles. All GPack validation stays in Goose; native I/O
// uses positional reads so independent calls never share a file cursor.
namespace reader;
import std;
import gpack;
import format;

let DEFAULT_MAX_ASSET_SIZE:   u64 = 32 * 1024 * 1024;
let SMALL_FRAME_ONE_SHOT_MAX: u64 = 1024 * 1024;
let STREAM_CHUNK_SIZE:        i64 = 1024 * 1024;

struct RuntimeEntry {
    path_start:     i64, path_len: i64, codec: u8, uncompressed_size: u64,
    payload_offset: u64, stored_size: u64, content_crc32: u32,
}
struct ArchiveInfo {
    format_major:       u16, format_minor: u16, file_size: u64, entry_count: u64,
    index_offset:       u64, index_size: u64, index_crc32: u32,
    raw_count:          u64, zstd_count: u64, empty_count: u64,
    uncompressed_bytes: u64, stored_bytes: u64,
}
struct ReadRequest { handle: u64, payload_offset: u64, size: u64, stored_size: u64, content_crc32: u32, codec: u8, ticket: u64 }
struct ReadResult { ticket: u64, ok: bool, bytes: u8[] }
struct VerifyResult { ticket: u64, ok: bool }

root struct Archive {
    handle:         u64               = 0,
    file_size:      u64               = 0,
    max_asset_size: u64               = DEFAULT_MAX_ASSET_SIZE,
    header:         format::Header    = format::Header { 0, 0, 0, 0 },
    path_bytes:     u8[>..]           = [],
    entries:        RuntimeEntry[>..] = [],
}

fn set_error(error: u8[>..]&, message: const u8[:]) {
    error.clear();
    error.append(message);
}

fn close(archive: Archive&) {
    if archive.handle != 0 { gpack::native_file_close(archive.handle); }
    archive.handle = 0;
    archive.file_size = 0;
    archive.entries.clear();
    archive.path_bytes.clear();
    archive.header = format::Header { 0, 0, 0, 0 };
}

fn open_detailed(path: const u8[:], archive: Archive&, max_asset_size: u64, error: u8[>..]&) -> bool {
    error.clear();
    if archive.handle != 0 || archive.entries.len != 0 || archive.path_bytes.len != 0 {
        set_error(error, "archive struct is already open");
        return false;
    }
    let handle = gpack::native_file_open_read(path);
    if handle == 0 {
        set_error(error, "cannot open archive file");
        return false;
    }
    let size = gpack::native_file_size(handle);
    if size == 0xffffffffffffffff || size < 68 {
        gpack::native_file_close(handle);
        set_error(error, "archive is unreadable or smaller than minimum v1 size");
        return false;
    }

    var header_bytes: u8[>..] = [];
    header_bytes.resize(format::HEADER_SIZE, 0);
    if gpack::native_file_read_at(handle, 0, header_bytes) != format::HEADER_SIZE {
        gpack::native_file_close(handle);
        set_error(error, "cannot read archive header");
        return false;
    }
    let header, header_ok = format::decode_header(header_bytes, size);
    if !header_ok {
        gpack::native_file_close(handle);
        set_error(error, "invalid v1 header or header CRC32 mismatch");
        return false;
    }
    var index_bytes: u8[>..] = [];
    index_bytes.resize(header.index_size as i64, 0);
    if gpack::native_file_read_at(handle, header.index_offset, index_bytes) != header.index_size as i64 {
        gpack::native_file_close(handle);
        set_error(error, "cannot read archive index");
        return false;
    }
    var parsed_entries: format::Entry[>..] = [];
    if !format::decode_index(index_bytes, header, parsed_entries) {
        parsed_entries.clear();
        gpack::native_file_close(handle);
        set_error(error, "invalid archive index or index CRC32 mismatch");
        return false;
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

fn open(path: const u8[:], archive: Archive&, max_asset_size: u64 = DEFAULT_MAX_ASSET_SIZE) -> bool {
    var error: u8[>..] = [];
    return open_detailed(path, archive, max_asset_size, error);
}

fn count(archive: Archive&) -> i64 {
    return archive.entries.len;
}

fn contains(archive: Archive&, path: const u8[:]) -> bool {
    return find(archive, path) >= 0;
}

fn entry_at(archive: Archive&, index: i64) -> RuntimeEntry, bool {
    if index < 0 || index >= archive.entries.len {
        return RuntimeEntry { 0, 0, 0, 0, 0, 0, 0 }, false;
    }
    return archive.entries[index], true;
}

fn info(archive: Archive&) -> ArchiveInfo {
    var raw_count:          u64 = 0;
    var zstd_count:         u64 = 0;
    var empty_count:        u64 = 0;
    var uncompressed_bytes: u64 = 0;
    var stored_bytes:       u64 = 0;
    for entry in archive.entries {
        uncompressed_bytes += entry.uncompressed_size;
        stored_bytes += entry.stored_size;
        if entry.uncompressed_size == 0 { empty_count += 1; }
        else if entry.codec == format::ZSTD { zstd_count += 1; }
        else { raw_count += 1; }
    }
    return ArchiveInfo {
        gpack::FORMAT_MAJOR, gpack::FORMAT_MINOR, archive.file_size,
        archive.header.entry_count, archive.header.index_offset,
        archive.header.index_size, archive.header.index_crc32,
        raw_count, zstd_count, empty_count, uncompressed_bytes, stored_bytes,
    };
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

fn request_detailed(archive: Archive&, path: const u8[:], ticket: u64, error: u8[>..]&) -> ReadRequest, bool {
    let empty = ReadRequest { 0, 0, 0, 0, 0, 0, 0 };
    error.clear();
    if archive.handle == 0 {
        set_error(error, "archive is not open");
        return empty, false;
    }
    if !format::valid_path(path) {
        set_error(error, str("invalid canonical asset path: ", path));
        return empty, false;
    }
    let i = find(archive, path);
    if i < 0 {
        set_error(error, str("asset not found: ", path));
        return empty, false;
    }
    let entry = archive.entries[i];
    if entry.uncompressed_size > archive.max_asset_size || entry.uncompressed_size > 0x7fffffffffffffff {
        set_error(error, str("asset exceeds configured max size: ", path));
        return empty, false;
    }
    if entry.codec != format::RAW && entry.codec != format::ZSTD {
        set_error(error, str("unsupported asset codec: ", path));
        return empty, false;
    }
    return ReadRequest { archive.handle, entry.payload_offset, entry.uncompressed_size, entry.stored_size, entry.content_crc32, entry.codec, ticket }, true;
}

fn request(archive: Archive&, path: const u8[:], ticket: u64 = 0) -> ReadRequest, bool {
    var error: u8[>..] = [];
    return request_detailed(archive, path, ticket, error);
}

fn zstd_fill_chunk(request: ReadRequest, input_buffer: u8[>..]&, input_offset: u64&, in_pos: i64&, in_len: i64&) -> bool {
    if in_pos < in_len { return true; }
    if input_offset >= request.stored_size { return false; }
    let count = min((request.stored_size - input_offset) as i64, input_buffer.len);
    if gpack::native_file_read_at(request.handle, request.payload_offset + input_offset, input_buffer[..count]) != count {
        return false;
    }
    in_pos = 0;
    in_len = count;
    return true;
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
        input_buffer.resize(STREAM_CHUNK_SIZE, 0);
        var input_offset:  u64 = 0;
        var output_offset: i64 = 0;
        var in_pos:        i64 = 0;
        var in_len:        i64 = 0;
        var done = false;
        var failed = false;
        while !done && !failed {
            if in_pos == in_len {
                if input_offset >= request.stored_size { break; }
                if !zstd_fill_chunk(request, input_buffer, input_offset, in_pos, in_len) {
                    failed = true; break;
                }
            }
            let step_end = min(output_offset + STREAM_CHUNK_SIZE, out.len);
            let result = gpack::native_zstd_decompress_step(context, input_buffer[in_pos..in_len], out[output_offset..step_end]);
            if result == 0xffffffffffffffff { failed = true; break; }
            let consumed = ((result >> 32) & 0x7fffffff) as i64;
            let produced = (result & 0x7fffffff) as i64;
            done = result & 0x8000000000000000 != 0;
            if consumed == 0 && produced == 0 && !done { failed = true; break; }
            in_pos += consumed;
            input_offset += consumed as u64;
            output_offset += produced;
        }
        if !done || input_offset != request.stored_size || output_offset != request.size as i64 { failed = true; }
        gpack::native_zstd_decompress_end(context);
        if failed { out.clear(); return false; }
    }
    if format::crc32(out) != request.content_crc32 { out.clear(); return false; }
    return true;
}

fn verify_request(request: ReadRequest) -> bool {
    if request.handle == 0 || request.size > 0x7fffffffffffffff || (request.codec != format::RAW && request.codec != format::ZSTD) { return false; }
    if request.size == 0 {
        return request.codec == format::RAW && request.stored_size == 0 && request.content_crc32 == 0;
    }
    var scratch: u8[>..] = [];
    scratch.resize(min(request.size as i64, STREAM_CHUNK_SIZE), 0);
    var crc_state: u32 = 0xffffffff;
    if request.codec == format::RAW {
        var offset: u64 = 0;
        while offset < request.size {
            let count = min((request.size - offset) as i64, scratch.len);
            let chunk = scratch[..count];
            if gpack::native_file_read_at(request.handle, request.payload_offset + offset, chunk) != count { return false; }
            crc_state = format::crc32_update(crc_state, chunk);
            offset += count as u64;
        }
        return ~crc_state == request.content_crc32;
    }
    if request.stored_size == 0 { return false; }
    let context = gpack::native_zstd_decompress_begin(window_log(request.size));
    if context == 0 { return false; }
    var input_buffer: u8[>..] = [];
    input_buffer.resize(min(request.stored_size as i64, STREAM_CHUNK_SIZE), 0);
    var input_offset:  u64 = 0;
    var decoded_total: u64 = 0;
    var in_pos:        i64 = 0;
    var in_len:        i64 = 0;
    var done = false;
    var failed = false;
    while !done && !failed {
        if in_pos == in_len {
            if input_offset >= request.stored_size { break; }
            if !zstd_fill_chunk(request, input_buffer, input_offset, in_pos, in_len) {
                failed = true; break;
            }
        }
        let result = gpack::native_zstd_decompress_step(context, input_buffer[in_pos..in_len], scratch);
        if result == 0xffffffffffffffff { failed = true; break; }
        let consumed = ((result >> 32) & 0x7fffffff) as i64;
        let produced = (result & 0x7fffffff) as i64;
        done = result & 0x8000000000000000 != 0;
        if consumed == 0 && produced == 0 && !done { failed = true; break; }
        if produced > 0 {
            if (produced as u64) > request.size - decoded_total { failed = true; break; }
            crc_state = format::crc32_update(crc_state, scratch[..produced]);
            decoded_total += produced as u64;
        }
        in_pos += consumed;
        input_offset += consumed as u64;
    }
    if !done || input_offset != request.stored_size || decoded_total != request.size { failed = true; }
    gpack::native_zstd_decompress_end(context);
    return !failed && ~crc_state == request.content_crc32;
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

thread_fn verify_worker(request: ReadRequest) {
    assert(qput(VerifyResult { request.ticket, verify_request(request) }));
}

// Reads one complete asset into out with a diagnostic error message on failure.
fn read_detailed(archive: Archive&, path: const u8[:], out: u8[>..]&, error: u8[>..]&) -> bool {
    out.clear();
    let req, ok = request_detailed(archive, path, 0, error);
    if !ok { return false; }
    if !read_request(req, out) {
        set_error(error, str("payload decode or CRC32/frame verification failed for: ", path));
        return false;
    }
    return true;
}

// Reads one complete raw asset into out. Separate output builders can be used
// concurrently with the same archive because the native operation is pread/
// overlapped I/O and the validated index is immutable after open.
fn read(archive: Archive&, path: const u8[:], out: u8[>..]&) -> bool {
    var error: u8[>..] = [];
    return read_detailed(archive, path, out, error);
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

fn verify_detailed(path: const u8[:], workers: i64, max_asset_size: u64,
                    verified_count: u64&, total_bytes: u64&,
                    failed_path: u8[>..]&, error: u8[>..]&) -> bool {
    verified_count = 0;
    total_bytes = 0;
    failed_path.clear();
    error.clear();
    if workers < 1 || workers > 16 {
        set_error(error, "worker count must be between 1 and 16");
        return false;
    }
    var archive = Archive { .. };
    if !open_detailed(path, archive, max_asset_size, error) { return false; }
    let total = archive.entries.len;
    if workers == 1 || total <= 1 {
        for i in total {
            let asset_path = path_at(archive, i);
            let req, req_ok = request(archive, asset_path, i as u64);
            if !req_ok {
                failed_path.append(asset_path);
                set_error(error, "asset exceeds configured max size");
                close(archive);
                return false;
            }
            if !verify_request(req) {
                failed_path.append(asset_path);
                set_error(error, "payload decode or CRC32/frame verification failed");
                close(archive);
                return false;
            }
            verified_count += 1;
            total_bytes += archive.entries[i].uncompressed_size;
        }
        close(archive);
        return true;
    }

    qlimit<VerifyResult>(workers);
    var next_index: i64      = 0;
    var in_flight:  i64      = 0;
    var handles:    i64[>..] = [];
    var pre_failed = false;
    var pre_failed_index: i64 = 0;
    var failed = false;
    var bad_ticket: u64 = 0;
    while (next_index < total && !failed && !pre_failed) || in_flight > 0 {
        while !failed && !pre_failed && in_flight < workers && next_index < total {
            let asset_path = path_at(archive, next_index);
            let req, req_ok = request(archive, asset_path, next_index as u64);
            if !req_ok {
                pre_failed = true;
                pre_failed_index = next_index;
                break;
            }
            handles.push(thread_spawn(verify_worker, req));
            in_flight += 1;
            next_index += 1;
        }
        if in_flight > 0 {
            let result = qget<VerifyResult>();
            in_flight -= 1;
            if !result.ok {
                if !failed || result.ticket < bad_ticket {
                    bad_ticket = result.ticket;
                }
                failed = true;
            } else {
                verified_count += 1;
                total_bytes += archive.entries[result.ticket as i64].uncompressed_size;
            }
        }
    }
    for handle in handles { thread_wait(handle); }
    if failed || pre_failed {
        if failed && (!pre_failed || bad_ticket < pre_failed_index as u64) {
            failed_path.append(path_at(archive, bad_ticket as i64));
            set_error(error, "payload decode or CRC32/frame verification failed");
        } else {
            failed_path.append(path_at(archive, pre_failed_index));
            set_error(error, "asset exceeds configured max size or invalid metadata");
        }
        close(archive);
        return false;
    }
    close(archive);
    return true;
}

fn verify(path: const u8[:], max_asset_size: u64 = DEFAULT_MAX_ASSET_SIZE) -> bool {
    var verified_count: u64     = 0;
    var total_bytes:    u64     = 0;
    var failed_path:    u8[>..] = [];
    var error:          u8[>..] = [];
    return verify_detailed(path, 4, max_asset_size, verified_count, total_bytes, failed_path, error);
}
