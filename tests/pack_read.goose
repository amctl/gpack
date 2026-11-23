import gpack from "../src/gpack";
import gpack.pack;
import gpack.reader;
import gpack.format;
import os;

thread_fn mutate_source() {
    sleep_ms(5);
    qput(write_file("build/pack-read-mutable-input/mutable.bin", "changed"));
}

fn has_gpack_temporary(directory: const u8[:]) -> bool {
    var names: u8[>..] = [];
    if !list_dir(directory, names) { return true; }
    var start = 0;
    while start < names.len {
        var end = start;
        while end < names.len && names[end] != '\n' { end++; }
        let name = names[start..end];
        if name.len >= 10 {
            for i in 0..name.len - 9 {
                if name[i..i + 10] == "gpack-tmp-" { return true; }
            }
        }
        start = end + 1;
    }
    return false;
}

fn write_frame_variant(source_path: const u8[:], output_path: const u8[:], concatenate: bool) -> bool {
    var archive = reader::Archive { .. };
    if !reader::open(source_path, archive) { return false; }
    let index = reader::find(archive, "only");
    if index < 0 { reader::close(archive); return false; }
    let entry = archive.entries[index];
    if entry.codec != format::ZSTD { reader::close(archive); return false; }
    var frame: u8[>..] = [];
    frame.resize(entry.stored_size as i64, 0);
    if gpack::native_file_read_at(archive.handle, entry.payload_offset, frame) != frame.len {
        reader::close(archive); return false;
    }
    var payload = copy(frame);
    if concatenate { payload.append(frame); }
    else { payload.push(0); }
    let bad_entry: format::Entry[1] = [format::Entry {
        "only", format::ZSTD, entry.uncompressed_size, 64, payload.len as u64, entry.content_crc32,
    }];
    let index_bytes, index_ok = format::encode_index(bad_entry);
    if !index_ok { reader::close(archive); return false; }
    let header = format::encode_header(format::Header {
        1, 64 + payload.len as u64, index_bytes.len as u64, format::crc32(index_bytes),
    });
    var damaged: u8[>..] = [];
    damaged.append(header); damaged.append(payload); damaged.append(index_bytes);
    reader::close(archive);
    return write_file(output_path, damaged);
}

fn assert_archive_golden(path: const u8[:], bytes: const u8[:]) {
    let digits = "0123456789abcdef";
    var actual: u8[>..] = [];
    for byte in bytes {
        actual.append([digits[(byte >> 4) as i64]]);
        actual.append([digits[(byte & 15) as i64]]);
    }
    var expected: u8[>..] = [];
    assert(read_file(path, expected));
    let expected_bytes = expected[..];
    let expected_text = if expected.len > 0 && expected[expected.len - 1] == '\n' {
        expected_bytes[..expected.len - 1]
    } else { expected_bytes };
    assert(actual == expected_text);
}

fn write_case_unicode_archive(path: const u8[:]) -> bool {
    let upper = "uppercase path";
    let lower = "lowercase path";
    let unicode = "UTF-8 path";
    var payload: u8[>..] = [];
    payload.append(upper);
    payload.append(lower);
    payload.append(unicode);
    let entries: format::Entry[3] = [
        format::Entry { "Case.txt", format::RAW, upper.len as u64, 64,
                        upper.len as u64, format::crc32(upper) },
        format::Entry { "case.txt", format::RAW, lower.len as u64,
                        64 + upper.len as u64, lower.len as u64,
                        format::crc32(lower) },
        format::Entry { "雪/猫.txt", format::RAW, unicode.len as u64,
                        64 + upper.len as u64 + lower.len as u64,
                        unicode.len as u64, format::crc32(unicode) },
    ];
    let index, ok = format::encode_index(entries);
    if !ok { return false; }
    let index_offset = 64 + payload.len as u64;
    let header = format::encode_header(format::Header {
        3, index_offset, index.len as u64, format::crc32(index),
    });
    var archive: u8[>..] = [];
    archive.append(header);
    archive.append(payload);
    archive.append(index);
    return write_file(path, archive);
}

fn main() {
    let root = "build/pack-read-input";
    assert(make_dir(root));
    assert(make_dir("build/pack-read-input/nested"));
    assert(write_file("build/pack-read-input/empty", ""));
    assert(write_file("build/pack-read-input/nested/small", "hello gpack"));
    let data0: u8[16] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
    let data1: u8[16] = [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31];
    let data2: u8[16] = [32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47];
    let data3: u8[16] = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63];
    assert(write_file("build/pack-read-input/parallel-0", data0));
    assert(write_file("build/pack-read-input/parallel-1", data1));
    assert(write_file("build/pack-read-input/parallel-2", data2));
    assert(write_file("build/pack-read-input/parallel-3", data3));
    var boundary: u8[>..] = [];
    for i in 1048577 { boundary.push((i % 251) as u8); }
    assert(write_file("build/pack-read-input/boundary", boundary));
    var noise:        u8[>..] = [];
    var random_state: u32     = 0x12345678;
    for _ in 65536 {
        random_state = random_state ^ (random_state << 13);
        random_state = random_state ^ (random_state >> 17);
        random_state = random_state ^ (random_state << 5);
        noise.push(random_state as u8);
    }
    assert(write_file("build/pack-read-input/incompressible", noise));

    let archive_path = "build/pack-read.gpk";
    let second_path = "build/pack-read-second.gpk";
    assert(pack::pack_directory(root, archive_path));
    assert(pack::pack_directory(root, second_path));
    var archive_bytes: u8[>..] = [];
    var second_bytes:  u8[>..] = [];
    assert(read_file(archive_path, archive_bytes));
    assert(read_file(second_path, second_bytes));
    assert(archive_bytes == second_bytes);

    let golden_path = "build/pack-read-cross-platform-golden.gpk";
    assert(pack::pack_directory("tests/fixtures/v1-golden-input", golden_path));
    var golden_bytes: u8[>..] = [];
    assert(read_file(golden_path, golden_bytes));
    assert_archive_golden("tests/fixtures/v1-golden-archive.hex", golden_bytes);
    assert(reader::verify(golden_path));

    let identity_path = "build/pack-read-case-unicode.gpk";
    assert(write_case_unicode_archive(identity_path));
    var identity_archive = reader::Archive { .. };
    assert(reader::open(identity_path, identity_archive));
    var identity_bytes: u8[>..] = [];
    assert(reader::read(identity_archive, "Case.txt", identity_bytes) && identity_bytes == "uppercase path");
    assert(reader::read(identity_archive, "case.txt", identity_bytes) && identity_bytes == "lowercase path");
    assert(reader::read(identity_archive, "雪/猫.txt", identity_bytes) && identity_bytes == "UTF-8 path");
    assert(!reader::read(identity_archive, "CASE.txt", identity_bytes));
    reader::close(identity_archive);

    var archive = reader::Archive { .. };
    assert(reader::open(archive_path, archive));
    var bytes: u8[>..] = [];
    assert(reader::read(archive, "empty", bytes) && bytes.len == 0);
    assert(reader::read(archive, "nested/small", bytes) && bytes == "hello gpack");
    assert(reader::read(archive, "boundary", bytes) && bytes == boundary);
    assert(reader::read(archive, "incompressible", bytes) && bytes == noise);
    let compressed_index = reader::find(archive, "boundary");
    let raw_index = reader::find(archive, "incompressible");
    assert(archive.entries[compressed_index].codec == format::ZSTD);
    assert(archive.entries[raw_index].codec == format::RAW);
    assert(!reader::read(archive, "missing", bytes));
    let r0, ok0 = reader::request(archive, "parallel-0", 0);
    let r1, ok1 = reader::request(archive, "parallel-1", 1);
    let r2, ok2 = reader::request(archive, "parallel-2", 2);
    let r3, ok3 = reader::request(archive, "parallel-3", 3);
    assert(ok0 && ok1 && ok2 && ok3);
    qlimit<reader::ReadResult>(4);
    let h0 = thread_spawn(reader::read_worker, r0);
    let h1 = thread_spawn(reader::read_worker, r1);
    let h2 = thread_spawn(reader::read_worker, r2);
    let h3 = thread_spawn(reader::read_worker, r3);
    for _ in 4 {
        let result = qget<reader::ReadResult>();
        assert(result.ok);
        if result.ticket == 0 { assert(result.bytes == data0); }
        else if result.ticket == 1 { assert(result.bytes == data1); }
        else if result.ticket == 2 { assert(result.bytes == data2); }
        else if result.ticket == 3 { assert(result.bytes == data3); }
        else { assert(false); }
    }
    thread_wait(h0); thread_wait(h1); thread_wait(h2); thread_wait(h3);
    assert(reader::verify(archive_path));
    reader::close(archive);
    assert(reader::open(archive_path, archive));

    // Metadata opens successfully after payload corruption; read and verify
    // must catch both compressed-frame and raw-content corruption.
    var compressed_damage = copy(archive_bytes);
    let compressed_entry = archive.entries[compressed_index];
    compressed_damage[compressed_entry.payload_offset + compressed_entry.stored_size - 1] =
        compressed_damage[compressed_entry.payload_offset + compressed_entry.stored_size - 1] ^ 0x80;
    let compressed_damage_path = "build/pack-read-compressed-damage.gpk";
    assert(write_file(compressed_damage_path, compressed_damage));
    var damaged_archive = reader::Archive { .. };
    assert(reader::open(compressed_damage_path, damaged_archive));
    assert(!reader::read(damaged_archive, "boundary", bytes));
    reader::close(damaged_archive);
    assert(reader::list(compressed_damage_path));
    assert(!reader::verify(compressed_damage_path));

    var raw_damage = copy(archive_bytes);
    let raw_entry = archive.entries[raw_index];
    raw_damage[raw_entry.payload_offset + raw_entry.stored_size / 2] =
        raw_damage[raw_entry.payload_offset + raw_entry.stored_size / 2] ^ 0x01;
    let raw_damage_path = "build/pack-read-raw-damage.gpk";
    assert(write_file(raw_damage_path, raw_damage));
    assert(reader::open(raw_damage_path, damaged_archive));
    assert(!reader::read(damaged_archive, "incompressible", bytes));
    reader::close(damaged_archive);
    assert(!reader::verify(raw_damage_path));
    reader::close(archive);

    var limited = reader::Archive { .. };
    assert(reader::open(archive_path, limited, 4));
    assert(!reader::read(limited, "nested/small", bytes));
    reader::close(limited);

    // The decoder accepts exactly one complete frame per compressed asset.
    assert(make_dir("build/pack-read-frame-input"));
    var frame_data: u8[>..] = [];
    for i in 262144 { frame_data.push((i % 197) as u8); }
    assert(write_file("build/pack-read-frame-input/only", frame_data));
    let frame_archive = "build/pack-read-frame.gpk";
    assert(pack::pack_directory("build/pack-read-frame-input", frame_archive));
    assert(write_frame_variant(frame_archive, "build/pack-read-trailing.gpk", false));
    assert(write_frame_variant(frame_archive, "build/pack-read-concatenated.gpk", true));
    assert(!reader::verify("build/pack-read-trailing.gpk"));
    assert(!reader::verify("build/pack-read-concatenated.gpk"));

    var changing: u8[>..] = [];
    for i in 16777216 { changing.push((i % 239) as u8); }
    assert(make_dir("build/pack-read-mutable-input"));
    assert(write_file("build/pack-read-mutable-input/mutable.bin", changing));
    let mutation_output_path = "build/pack-read-mutation.gpk";
    assert(write_file(mutation_output_path, "preserve-existing-archive"));
    let mutator = thread_spawn(mutate_source);
    let pack_ok = pack::pack_directory("build/pack-read-mutable-input", mutation_output_path);
    let mutation_applied = qget<bool>();
    thread_wait(mutator);
    assert(if mutation_applied { !pack_ok } else { pack_ok });
    if mutation_applied {
        var preserved: u8[>..] = [];
        assert(read_file(mutation_output_path, preserved));
        assert(preserved == "preserve-existing-archive");
        assert(!has_gpack_temporary("build"));
    }
}
