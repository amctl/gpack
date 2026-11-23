import std;
import os;
import dictionary;

extern fn h3_reader_open(path: const u8[:]) -> i32;
extern fn h3_reader_size(fd: i32) -> i64;
extern fn h3_reader_read_at(fd: i32, offset: i64, output: u8[:]) -> i64;
extern fn h3_reader_close(fd: i32) -> i32;
extern fn h3_reader_decompress(input: u8[:], output: u8[:]) -> i64;

struct Job { sequence: i32, fd: i32, offset: i64, compressed_size: i64,
             raw_size: i64, expected_crc: u32 }
struct Result { sequence: i32, crc: u32, bytes: i64, elapsed_ns: i64 }

fn fail(message: const u8[:]) { print(message); exit(1); }

fn read_u32(data: u8[:], at: i64) -> u32 {
    guard at >= 0 && at <= data.len - 4 else { fail("truncated u32"); }
    return (data[at] as u32) | ((data[at + 1] as u32) << 8) |
           ((data[at + 2] as u32) << 16) | ((data[at + 3] as u32) << 24);
}
fn read_u64(data: u8[:], at: i64) -> u64 {
    guard at >= 0 && at <= data.len - 8 else { fail("truncated u64"); }
    var value: u64 = 0;
    for i in 8 { value |= (data[at + i] as u64) << (i * 8); }
    return value;
}

fn append_zeroes(out: u8[>..]&, size: i64) {
    guard size >= 0 else { fail("negative buffer size"); }
    for i in size { out.push(0); }
}

fn safe_path(path: u8[:]) -> bool {
    if path.len == 0 || path[0] == '/' { return false; }
    var safe = true;
    for byte in path { if byte == '\\' || byte == 0 { safe = false; } }
    each_split(path, '/') { part =>
        if part.len == 0 || part == "." || part == ".." { safe = false; }
    };
    return safe;
}

fn crc32(data: u8[:]) -> u32 {
    var crc: u32 = 0xffffffff;
    for byte in data {
        crc ^= byte as u32;
        for bit in 8 { crc = if (crc & 1) != 0 { (crc >> 1) ^ 0xedb88320 } else { crc >> 1 }; }
    }
    return ~crc;
}

fn parse_jobs(fd: i32, archive_size: i64, expected_text: u8[:],
              jobs: Job[>..]&, path_lookup: dictionary<const u8[:], u32>&,
              index: u8[>..]&) {
    var expected = dictionary<const u8[:], u32> {};
    each_split(expected_text, '\n') { line =>
        if line.len > 0 {
            let fields = split(line, '\t');
            guard fields.len == 2 && safe_path(fields[0]) else { fail("bad expected-hash manifest"); }
            let value, valid = parse_int(fields[1]);
            guard valid && value >= 0 && value <= 0xffffffff else { fail("bad expected CRC32"); }
            guard expected.insert(fields[0], value as! u32) else { fail("duplicate expected path"); }
        }
    };

    var header: u8[>..] = [];
    append_zeroes(header, 32);
    guard h3_reader_read_at(fd, 0, header) == 32 else { fail("truncated archive header"); }
    guard header[..8] == "GPKH2\0\0\0" else { fail("bad archive magic"); }
    guard read_u32(header, 8) == 1 && read_u32(header, 12) == 1 else { fail("unsupported archive version or layout"); }
    let file_count = read_u64(header, 16);
    let index_offset_u = read_u64(header, 24);
    guard file_count <= 1000000 && archive_size >= 36 &&
          index_offset_u >= 32 && index_offset_u <= (archive_size - 4) as u64 else {
        fail("archive header range is invalid");
    }
    let index_offset = index_offset_u as! i64;
    let index_size = archive_size - index_offset;
    guard index_size >= 4 && index_size <= 64 * 1024 * 1024 else { fail("index size is invalid"); }
    append_zeroes(index, index_size);
    guard h3_reader_read_at(fd, index_offset, index) == index_size else { fail("truncated archive index"); }
    guard read_u32(index, 0) as u64 == file_count else { fail("archive file count mismatch"); }

    var at = 4;
    var previous_start: i64 = -1;
    var previous_len: i64 = 0;
    for sequence in file_count as! i64 {
        guard at <= index.len - 16 else { fail("truncated file record"); }
        let path_len = read_u32(index, at) as! i64; at += 4;
        let asset_size_u = read_u64(index, at); at += 8;
        let segment_count = read_u32(index, at); at += 4;
        guard path_len > 0 && path_len <= 1024 * 1024 && asset_size_u <= (8 * 1024 * 1024 * 1024) as u64 && segment_count == 1 else {
            fail("invalid file metadata");
        }
        guard at <= index.len - path_len else { fail("truncated asset path"); }
        let path_start = at;
        let path = index[at..at + path_len]; at += path_len;
        guard safe_path(path) else { fail("unsafe archive path"); }
        if previous_start >= 0 && compare(index[previous_start..previous_start + previous_len], path) >= 0 { fail("duplicate or unsorted archive path"); }
        previous_start = path_start;
        previous_len = path_len;
        guard at <= index.len - 24 else { fail("truncated segment record"); }
        let offset_u = read_u64(index, at); at += 8;
        let compressed_u = read_u64(index, at); at += 8;
        let raw_u = read_u64(index, at); at += 8;
        guard offset_u >= 32 && offset_u <= index_offset_u && compressed_u > 0 &&
              compressed_u <= index_offset_u - offset_u && raw_u == asset_size_u else {
            fail("segment range is out of bounds");
        }
        let crc = expected.get(path);
        guard crc else { fail("archive path has no expected source hash"); }
        guard path_lookup.insert(path, sequence as! u32) else { fail("duplicate archive path"); }
        jobs.push(Job { sequence: sequence as! i32, fd: fd,
                        offset: offset_u as! i64, compressed_size: compressed_u as! i64,
                        raw_size: raw_u as! i64, expected_crc: crc });
    }
    guard at == index.len && expected.count == jobs.len else { fail("index trailing bytes or path-count mismatch"); }
}

thread_fn reader() {
    loop {
        let job = qget<Job>();
        guard job.sequence >= 0 else { break; }
        let started = clock_ns();
        var encoded: u8[>..] = [];
        append_zeroes(encoded, job.compressed_size);
        guard h3_reader_read_at(job.fd, job.offset, encoded) == job.compressed_size else { abort("short positional read"); }
        var decoded: u8[>..] = [];
        append_zeroes(decoded, job.raw_size);
        guard h3_reader_decompress(encoded, decoded) == job.raw_size else { abort("invalid Zstandard frame"); }
        let sum = crc32(decoded);
        let elapsed = clock_ns() - started;
        while !qput(Result { sequence: job.sequence, crc: sum, bytes: job.raw_size, elapsed_ns: elapsed }) {
            sleep_ms(1);
        }
    }
}

fn main() {
    guard arg_count() >= 3 else { print("usage: runtime_driver ARCHIVE EXPECTED_CRC_TSV [validate]"); exit(2); }
    var archive_path: u8[>..] = []; arg(1, archive_path);
    var expected_path: u8[>..] = []; arg(2, expected_path);
    let parse_started = clock();
    var expected: u8[>..] = [];
    guard read_file(expected_path, expected) else { fail("cannot read expected hash manifest"); }
    let fd = h3_reader_open(archive_path);
    guard fd >= 0 else { fail("cannot open archive"); }
    let archive_size = h3_reader_size(fd);
    guard archive_size >= 0 else { h3_reader_close(fd); fail("cannot stat archive"); }
    var jobs: Job[>..] = [];
    var path_lookup = dictionary<const u8[:], u32> {};
    var index: u8[>..] = [];
    parse_jobs(fd, archive_size, expected, jobs, path_lookup, index);
    let parse_seconds = clock() - parse_started;
    if arg_count() > 3 {
        h3_reader_close(fd);
        print("VALID ", jobs.len);
        return;
    }

    let readers = 4;
    var max_working: i64 = 0;
    for job in jobs { max_working = max(max_working, job.raw_size + job.compressed_size); }
    qlimit<Job>(jobs.len + readers);
    qlimit<Result>(readers * 2);
    let lookup_started = clock();
    var queued = 0;
    each_split(expected, '\n') { line =>
        if line.len > 0 {
            let fields = split(line, '\t');
            guard fields.len == 2 else { h3_reader_close(fd); fail("bad query path row"); }
            let sequence = path_lookup.get(fields[0]);
            guard sequence else { h3_reader_close(fd); fail("runtime path lookup failed"); }
            guard qput(jobs[sequence]) else { h3_reader_close(fd); fail("lookup job queue refused work"); }
            queued++;
        }
    };
    guard queued == jobs.len else { h3_reader_close(fd); fail("query count differs from index count"); }
    for i in readers {
        guard qput(Job { sequence: -1, fd: fd, offset: 0, compressed_size: 0, raw_size: 0, expected_crc: 0 })
            else { h3_reader_close(fd); fail("lookup queue refused stop"); }
    }
    var ids: i64[>..] = [];
    for i in readers { ids.push(thread_spawn(reader)); }
    var latencies: i64[>..] = [];
    latencies.resize(jobs.len, 0);
    var total_bytes: i64 = 0;
    for received in jobs.len {
        let result = qget<Result>();
        guard result.sequence >= 0 && result.sequence < jobs.len else { abort("invalid reader result sequence"); }
        guard result.crc == jobs[result.sequence].expected_crc else { abort("asset CRC differs from source"); }
        latencies[result.sequence] = result.elapsed_ns;
        total_bytes += result.bytes;
    }
    for id in ids { guard thread_wait(id) else { abort("reader thread failed"); } }
    let lookup_seconds = clock() - lookup_started;
    guard h3_reader_close(fd) == 0 else { fail("cannot close archive"); }
    sort(latencies) { a, b => a < b };
    let p50 = if latencies.len > 0 { latencies[(latencies.len - 1) / 2] } else { 0 };
    let p95 = if latencies.len > 0 { latencies[((latencies.len - 1) * 95 / 100)] } else { 0 };
    let mib_s = total_bytes as f64 / 1048576.0 / lookup_seconds;
    print("H3RUNTIME goose ", jobs.len, " ", total_bytes, " ", parse_seconds, " ",
          lookup_seconds, " ", mib_s, " ", p50 as f64 / 1000000.0, " ", p95 as f64 / 1000000.0,
          " ", max_working);
}
