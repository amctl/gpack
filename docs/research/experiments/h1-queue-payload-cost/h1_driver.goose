import std;
import os;

extern fn h3_compress_bytes(input: const u8[:], output: u8[:]) -> i64;

struct Job {
    sequence: i32,
    source: u8[],
    stage: u8[],
    asset: u8[],
    offset: i64,
    size: i64,
}
struct Payload { sequence: i32, stage: u8[], bytes: u8[] }
struct Done { sequence: i32, size: i64, stage: u8[] }

fn append_u32le(out: u8[>..]&, value: u32) {
    for byte in 4 { out.push((value >> (byte * 8)) as! u8); }
}
fn append_u64le(out: u8[>..]&, value: u64) {
    for byte in 8 { out.push((value >> (byte * 8)) as! u8); }
}

fn compress_job(job: Job&) -> u8[>..] {
    var raw: u8[>..] = [];
    guard read_file(job.source, raw) else { abort("worker cannot read chunk input"); }
    guard raw.len == job.size else { abort("chunk input size changed"); }
    var encoded: u8[>..] = [];
    let bound = raw.len + raw.len / 8 + 256;
    for i in bound { encoded.push(0); }
    let size = h3_compress_bytes(raw, encoded);
    guard size >= 0 else { abort("chunk compression failed"); }
    var result: u8[>..] = [];
    result.append(encoded[..size]);
    return result;
}

thread_fn payload_worker() {
    loop {
        let job = qget<Job>();
        guard job.sequence >= 0 else { break; }
        let bytes = compress_job(job);
        let result = Payload { sequence: job.sequence, stage: copy(job.stage), bytes: copy(bytes) };
        while !qput(result) { sleep_ms(1); }
    }
}

thread_fn staged_worker() {
    loop {
        let job = qget<Job>();
        guard job.sequence >= 0 else { break; }
        let bytes = compress_job(job);
        guard write_file(job.stage, bytes) else { abort("worker cannot stage compressed chunk"); }
        let result = Done { sequence: job.sequence, size: bytes.len, stage: copy(job.stage) };
        while !qput(result) { sleep_ms(1); }
    }
}

fn main() {
    guard arg_count() >= 5 else { print("usage: h1_driver MODE MANIFEST WORKERS OUTPUT"); exit(2); }
    var mode: u8[>..] = []; arg(1, mode);
    var manifest_path: u8[>..] = []; arg(2, manifest_path);
    var worker_text: u8[>..] = []; arg(3, worker_text);
    var output_path: u8[>..] = []; arg(4, output_path);
    let worker_count, worker_ok = parse_int(worker_text);
    guard worker_ok && worker_count >= 1 else { print("invalid worker count"); exit(2); }
    var manifest: u8[>..] = [];
    guard read_file(manifest_path, manifest) else { print("cannot read manifest"); exit(1); }
    var lines: u8[:][>..] = [];
    each_split(manifest, '\n') { line => if line.len > 0 { lines.push(line); } };
    var jobs: Job[>..] = [];
    for line in lines {
        let fields = split(line, '\t');
        guard fields.len == 6 else { print("bad H1 chunk manifest row"); exit(1); }
        let sequence, seq_ok = parse_int(fields[0]);
        let offset, off_ok = parse_int(fields[4]);
        let size, size_ok = parse_int(fields[5]);
        guard seq_ok && off_ok && size_ok && sequence == jobs.len && offset >= 0 && size >= 0 else {
            print("invalid H1 chunk manifest values"); exit(1);
        }
        jobs.push(Job { sequence: sequence as! i32, source: fields[1], stage: fields[2],
                        asset: fields[3], offset: offset, size: size });
    }
    guard jobs.len > 0 else { print("empty H1 manifest"); exit(1); }
    var temp_path: u8[>..] = [];
    temp_path.append(output_path);
    temp_path.append(".tmp");
    let started = clock();

    if mode == "serial" {
        for job in jobs {
            let bytes = compress_job(job);
            guard write_file(job.stage, bytes) else { print("cannot stage serial result"); exit(1); }
        }
    } else if mode == "payload" || mode == "stage" {
        qlimit<Job>(jobs.len + worker_count);
        if mode == "payload" { qlimit<Payload>(worker_count * 2); }
        else { qlimit<Done>(worker_count * 2); }
        for job in jobs { guard qput(job) else { print("job queue refused input"); exit(1); } }
        for i in worker_count {
            guard qput(Job { sequence: -1, source: [], stage: [], asset: [], offset: 0, size: 0 })
                else { print("job queue refused stop"); exit(1); }
        }
        var ids: i64[>..] = [];
        for i in worker_count {
            ids.push(if mode == "payload" { thread_spawn(payload_worker) } else { thread_spawn(staged_worker) });
        }
        var ready: bool[>..] = [];
        ready.resize(jobs.len, false);
        for received in jobs.len {
            if mode == "payload" {
                let result = qget<Payload>();
                guard result.sequence >= 0 && result.sequence < jobs.len else { abort("invalid payload result sequence"); }
                guard write_file(result.stage, result.bytes) else { abort("cannot stage queued payload"); }
                ready[result.sequence] = true;
            } else {
                let result = qget<Done>();
                guard result.sequence >= 0 && result.sequence < jobs.len else { abort("invalid metadata result sequence"); }
                guard file_exists(result.stage) else { abort("staged result is missing"); }
                ready[result.sequence] = true;
            }
        }
        for id in ids { guard thread_wait(id) else { abort("worker failed"); } }
        for i in jobs.len { guard ready[i] else { abort("result was not received"); } }
    } else {
        print("mode must be payload, stage, or serial"); exit(2);
    }

    let processed = clock() - started;
    let assembly_started = clock();
    var header: u8[>..] = [];
    header.append("GPKH1\0\0\0");
    append_u32le(header, jobs.len as! u32);
    guard write_file(temp_path, header) else { print("cannot create H1 archive"); exit(1); }
    for job in jobs {
        var payload: u8[>..] = [];
        guard read_file(job.stage, payload) else { print("cannot read staged H1 chunk"); exit(1); }
        var record: u8[>..] = [];
        append_u32le(record, job.sequence as! u32);
        append_u32le(record, job.asset.len as! u32);
        append_u64le(record, job.offset as! u64);
        append_u32le(record, job.size as! u32);
        append_u32le(record, payload.len as! u32);
        record.append(job.asset);
        guard append_file(temp_path, record) && append_file(temp_path, payload) else {
            print("cannot append H1 archive record"); exit(1);
        }
        guard delete_file(job.stage) else { print("cannot remove staged H1 chunk"); exit(1); }
    }
    guard rename_file(temp_path, output_path) else { print("cannot finalize H1 archive"); exit(1); }
    let assembly = clock() - assembly_started;
    let elapsed = clock() - started;
    print("H1RESULT ", mode, " ", worker_count, " ", jobs.len, " ", processed, " ", assembly, " ", elapsed);
}
