import std;
import os;
import gpack from "../../../../src/gpack";
import zip_reader;

struct Job { stop: bool, request: zip_reader::ReadRequest }
struct Result { bytes: u64, elapsed_ns: u64, ok: bool }

fn stop_job() -> Job { return Job { true, zip_reader::ReadRequest { 0, 0, 0, 0, 0, 0, 0 } }; }

thread_fn worker() {
    loop {
        let job = qget<Job>();
        if job.stop { return; }
        let started = clock_ns();
        var bytes: u8[>..] = [];
        let ok = zip_reader::read_request(job.request, bytes);
        let elapsed = clock_ns() - started;
        while !qput(Result { job.request.uncompressed_size, elapsed as u64, ok }) { sleep_ms(1); }
    }
}

fn fail(message: const u8[:]) { print(message); exit(1); }

fn load_manifest(path: const u8[:], manifest: u8[>..]&) -> bool { return read_file(path, manifest); }

fn check_manifest(archive: zip_reader::Archive&, manifest: const u8[:], do_reads: bool) -> i64 {
    var rows: i64 = 0;
    each_split(manifest, '\n') { line =>
        if line.len > 0 {
            let fields = split(line, '\t');
            guard fields.len == 2 else { abort("invalid source CRC manifest"); }
            let parsed, parsed_ok = parse_int(fields[1]);
            guard parsed_ok && parsed >= 0 && parsed <= 0xffffffff else { abort("invalid source CRC value"); }
            let request, found = zip_reader::request(archive, fields[0]);
            guard found else { abort("source path missing or above default limit"); }
            guard request.crc32 == parsed as u32 else { abort("ZIP CRC differs from source manifest"); }
            if do_reads {
                var bytes: u8[>..] = [];
                guard zip_reader::read_request(request, bytes) else { abort("ZIP member read/CRC failed"); }
                guard bytes.len as u64 == request.uncompressed_size else { abort("ZIP member size mismatch"); }
            }
            rows++;
        }
    };
    return rows;
}

fn main() {
    guard arg_count() == 3 || arg_count() == 4 else { print("usage: zip_runtime_driver ARCHIVE SOURCE_CRC_TSV [validate]"); exit(2); }
    var archive_path:  u8[>..] = []; arg(1, archive_path);
    var manifest_path: u8[>..] = []; arg(2, manifest_path);
    var manifest:      u8[>..] = [];
    guard load_manifest(manifest_path, manifest) else { fail("cannot read source manifest"); }
    var archive = zip_reader::Archive { .. };
    let parse_started = clock_ns();
    guard zip_reader::open(archive_path, archive) else { fail("invalid restricted ZIP"); }
    let parse_ns = clock_ns() - parse_started;
    if arg_count() == 4 {
        let count = check_manifest(archive, manifest, true);
        zip_reader::close(archive);
        print("VALID ", count);
        return;
    }

    var jobs: Job[>..] = [];
    each_split(manifest, '\n') { line =>
        if line.len > 0 {
            let fields = split(line, '\t');
            guard fields.len == 2 else { fail("invalid source CRC manifest"); }
            let parsed, parsed_ok = parse_int(fields[1]);
            guard parsed_ok && parsed >= 0 && parsed <= 0xffffffff else { fail("invalid source CRC value"); }
            let request, found = zip_reader::request(archive, fields[0]);
            guard found && request.crc32 == parsed as u32 else { fail("source entry missing or CRC mismatch"); }
            let job: Job[1] = [Job { false, request }];
            jobs.append(job);
        }
    };
    guard jobs.len > 0 else { fail("empty benchmark workload"); }
    qlimit<Job>(jobs.len + 4); qlimit<Result>(8);
    let lookup_started = clock_ns();
    for job in jobs { assert(qput(job)); }
    for _ in 4 { assert(qput(stop_job())); }
    var workers: i64[4] = [0, 0, 0, 0];
    for i in 0..4 { workers[i] = thread_spawn(worker); }
    var latencies:   u64[>..] = [];
    var total_bytes: u64      = 0;
    for _ in jobs.len {
        let result = qget<Result>();
        guard result.ok else { abort("ZIP read or CRC failed"); }
        latencies.push(result.elapsed_ns);
        total_bytes += result.bytes;
    }
    for handle in workers { guard thread_wait(handle) else { abort("ZIP worker failed"); } }
    let lookup_ns = clock_ns() - lookup_started;
    zip_reader::close(archive);
    sort(latencies) { a, b => a < b };
    let p50 = latencies[(latencies.len - 1) / 2];
    let p95 = latencies[(latencies.len - 1) * 95 / 100];
    let mib_s = total_bytes as f64 * 1000000000.0 / lookup_ns as f64 / 1048576.0;
    print("ZIPV1 goose ", jobs.len, " ", total_bytes, " ", parse_ns, " ", lookup_ns,
          " ", mib_s, " ", p50 as f64 / 1000000.0, " ", p95 as f64 / 1000000.0);
}
