import gpack from "../../../../src/gpack";
import gpack.reader;
import os;

struct Job { stop: bool, request: reader::ReadRequest }
struct Result { bytes: u64, elapsed_ns: u64, ok: bool }

fn stop_job() -> Job {
    return Job { true, reader::ReadRequest { 0, 0, 0, 0, 0, 0, 0 } };
}

thread_fn worker() {
    loop {
        let job = qget<Job>();
        if job.stop { return; }
        let started = clock_ns();
        var bytes: u8[>..] = [];
        let ok = reader::read_request(job.request, bytes);
        let elapsed = clock_ns() - started;
        let result = Result { job.request.size, elapsed as u64, ok };
        while !qput(result) { sleep_ms(1); }
    }
}

fn fail(message: const u8[:]) { print(message); exit(1); }

fn main() {
    guard arg_count() == 3 || arg_count() == 4 else { print("usage: runtime_driver ARCHIVE SOURCE_CRC_TSV [validate]"); exit(2); }
    var archive_path:  u8[>..] = []; arg(1, archive_path);
    var manifest_path: u8[>..] = []; arg(2, manifest_path);
    var manifest:      u8[>..] = [];
    guard read_file(manifest_path, manifest) else { fail("cannot read manifest"); }
    var archive = reader::Archive { .. };
    let parse_started = clock_ns();
    guard reader::open(archive_path, archive) else { fail("invalid v1 archive"); }
    let parse_ns = clock_ns() - parse_started;
    if arg_count() == 4 {
        reader::close(archive);
        print("VALID");
        return;
    }

    var jobs: Job[>..] = [];
    each_split(manifest, '\n') { line =>
        if line.len > 0 {
            let fields = split(line, '\t');
            guard fields.len == 2 else { fail("invalid manifest row"); }
            let parsed, valid = parse_int(fields[1]);
            guard valid && parsed >= 0 && parsed <= 0xffffffff else { fail("invalid CRC32"); }
            let request, found = reader::request(archive, fields[0]);
            guard found else { fail("source path missing or above reader size cap"); }
            guard request.content_crc32 == parsed as! u32 else { fail("archive CRC differs from source CRC"); }
            let job: Job[1] = [Job { false, request }];
            jobs.append(job);
        }
    };
    guard jobs.len > 0 else { fail("empty benchmark workload"); }
    qlimit<Job>(jobs.len + 4);
    qlimit<Result>(8);
    let lookup_started = clock_ns();
    for job in jobs { assert(qput(job)); }
    for _ in 4 { assert(qput(stop_job())); }
    var workers: i64[4] = [0, 0, 0, 0];
    for i in 0..4 { workers[i] = thread_spawn(worker); }
    var latencies:   u64[>..] = [];
    var total_bytes: u64      = 0;
    for _ in jobs.len {
        let result = qget<Result>();
        guard result.ok else { abort("read or content CRC mismatch"); }
        latencies.push(result.elapsed_ns);
        total_bytes += result.bytes;
    }
    for handle in workers { guard thread_wait(handle) else { abort("worker failed"); } }
    let lookup_ns = clock_ns() - lookup_started;
    reader::close(archive);
    sort(latencies) { a, b => a < b };
    let p50 = latencies[(latencies.len - 1) / 2];
    let p95 = latencies[(latencies.len - 1) * 95 / 100];
    let mib_s = total_bytes as f64 * 1000000000.0 / lookup_ns as f64 / 1048576.0;
    print("GPKV1 goose ", jobs.len, " ", total_bytes, " ", parse_ns, " ", lookup_ns,
          " ", mib_s, " ", p50 as f64 / 1000000.0, " ", p95 as f64 / 1000000.0);
}
