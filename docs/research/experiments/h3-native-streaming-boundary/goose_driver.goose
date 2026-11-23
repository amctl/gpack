import std;
import os;

extern fn h3_begin(path: const u8[:]) -> bool;
extern fn h3_write(data: const u8[:]) -> bool;
extern fn h3_compress_file(path: const u8[:]) -> bool;
extern fn h3_finish() -> bool;
extern fn h3_abort();
extern fn h3_compress_bytes(input: const u8[:], output: u8[:]) -> i64;

fn append_u32le(out: u8[>..]&, value: u32) {
    for byte in 4 { out.push((value >> (byte * 8)) as! u8); }
}

fn append_u64le(out: u8[>..]&, value: u64) {
    for byte in 8 { out.push((value >> (byte * 8)) as! u8); }
}

fn main() {
    guard arg_count() >= 4 else { print("usage: goose_driver MODE MANIFEST OUTPUT"); exit(2); }
    var mode: u8[>..] = []; arg(1, mode);
    var manifest_path: u8[>..] = []; arg(2, manifest_path);
    var output_path: u8[>..] = []; arg(3, output_path);
    var manifest: u8[>..] = [];
    guard read_file(manifest_path, manifest) else { print("cannot read manifest"); exit(1); }

    var records: u8[:][>..] = [];
    each_split(manifest, '\n') { line =>
        if line.len > 0 { records.push(line); }
    };
    var output: u8[>..] = [];
    output.append("GPKH3\0\0\0");
    append_u32le(output, records.len as! u32);

    if mode == "native" {
        guard h3_begin(output_path) else { print("cannot create native output"); exit(1); }
        if !h3_write(output) { h3_abort(); print("native header write failed"); exit(1); }
    }

    for line in records {
        let fields = split(line, '\t');
        guard fields.len == 3 else { print("bad manifest record"); exit(1); }
        let size, valid_size = parse_int(fields[2]);
        guard valid_size && size >= 0 else { print("bad manifest size"); exit(1); }
        let source_path = fields[0];
        let asset_path = fields[1];
        var record: u8[>..] = [];
        append_u32le(record, asset_path.len as! u32);
        append_u64le(record, size as! u64);
        record.append(asset_path);

        if mode == "native" {
            if !h3_write(record) || !h3_compress_file(source_path) {
                h3_abort(); print("native streaming write failed"); exit(1);
            }
        } else {
            var raw: u8[>..] = [];
            guard read_file(source_path, raw) else { print("cannot read asset"); exit(1); }
            guard raw.len == size else { print("source size changed"); exit(1); }
            var compressed: u8[>..] = [];
            let compressed_bound = raw.len + raw.len / 8 + 256;
            for i in compressed_bound { compressed.push(0); }
            let compressed_size = h3_compress_bytes(raw, compressed);
            guard compressed_size >= 0 else { print("compression failed"); exit(1); }
            output.append(record);
            output.append(compressed[..compressed_size]);
        }
    }

    if mode == "native" {
        guard h3_finish() else { h3_abort(); print("native finalization failed"); exit(1); }
    } else {
        guard write_file_atomic(output_path, output) else { print("cannot write output"); exit(1); }
    }
}
