import gpack from "../src/gpack";
import gpack.format;
import os;

fn assert_golden(path: const u8[:], bytes: const u8[:]) {
    let digits = "0123456789abcdef";
    var actual: u8[>..] = [];
    for byte in bytes {
        actual.append([digits[(byte >> 4) as i64]]);
        actual.append([digits[(byte & 15) as i64]]);
    }
    var expected: u8[>..] = [];
    assert(read_file(path, expected));
    let expected_bytes = expected[..];
    let expected_text = if expected.len > 0 && expected[expected.len - 1] == '\n' { expected_bytes[..expected.len - 1] } else { expected_bytes };
    assert(actual == expected_text);
}

fn main() {
    assert(format::crc32("123456789") == 0xcbf43926);
    assert(format::valid_path("textures/player.png"));
    assert(!format::valid_path(""));
    assert(!format::valid_path("."));
    assert(!format::valid_path(".."));
    assert(!format::valid_path("a/./b"));
    assert(!format::valid_path("../secret"));
    assert(!format::valid_path("a/../b"));
    assert(!format::valid_path("/a"));
    assert(!format::valid_path("a/"));
    assert(!format::valid_path("a//b"));
    assert(!format::valid_path("a\\b"));
    let nul_path: u8[3] = ['a', 0, 'b'];
    assert(!format::valid_path(nul_path));
    var long_path: u8[>..] = [];
    for _ in 4097 { long_path.push('a'); }
    assert(!format::valid_path(long_path));
    let invalid_utf8: u8[2] = [0xc0, 0xaf];
    assert(!format::valid_path(invalid_utf8));
    let surrogate_utf8: u8[3] = [0xed, 0xa0, 0x80];
    assert(!format::valid_path(surrogate_utf8));
    let truncated_utf8: u8[1] = [0xc2];
    assert(!format::valid_path(truncated_utf8));
    let out_of_range_utf8: u8[4] = [0xf4, 0x90, 0x80, 0x80];
    assert(!format::valid_path(out_of_range_utf8));

    let index: u8[4] = [0, 0, 0, 0];
    let header_bytes = format::encode_header(format::Header { 0, 64, 4, 0x2144df1c });
    assert_golden("tests/fixtures/v1-empty-header.hex", header_bytes);
    let header, header_ok = format::decode_header(header_bytes, 68);
    assert(header_ok && header.entry_count == 0 && header.index_offset == 64 && header.index_size == 4);
    var wrong_version = header_bytes;
    wrong_version[8] = 2;
    let wrong_version_crc = format::crc32_header(wrong_version);
    for i in 0..4 { wrong_version[44 + i] = (wrong_version_crc >> (i * 8)) as u8; }
    let _, wrong_version_ok = format::decode_header(wrong_version, 68);
    assert(!wrong_version_ok);
    var reserved_header_bytes = header_bytes;
    reserved_header_bytes[48] = 1;
    let reserved_crc = format::crc32_header(reserved_header_bytes);
    for i in 0..4 { reserved_header_bytes[44 + i] = (reserved_crc >> (i * 8)) as u8; }
    let _, reserved_header_ok = format::decode_header(reserved_header_bytes, 68);
    assert(!reserved_header_ok);
    var wrong_header_crc = header_bytes;
    wrong_header_crc[44] = wrong_header_crc[44] ^ 1;
    let _, wrong_header_crc_ok = format::decode_header(wrong_header_crc, 68);
    assert(!wrong_header_crc_ok);

    var entries: format::Entry[>..] = [];
    assert(format::decode_index(index, header, entries));
    assert(entries.len == 0);
    let encoded_empty_index, empty_encode_ok = format::encode_index(entries);
    assert(empty_encode_ok);
    assert_golden("tests/fixtures/v1-empty-index.hex", encoded_empty_index);
    assert(encoded_empty_index.len == index.len);
    for i in 0..index.len { assert(encoded_empty_index[i] == index[i]); }
    let bad_index: u8[5] = [0, 0, 0, 0, 0];
    assert(!format::decode_index(bad_index, header, entries));
    let wrong_index_count = format::Header { 1, 64, 4, format::crc32(index) };
    assert(!format::decode_index(index, wrong_index_count, entries));
    let wrong_index_crc = format::Header { 0, 64, 4, 0 };
    assert(!format::decode_index(index, wrong_index_crc, entries));

    let asset: format::Entry[1] = [format::Entry { "a", format::RAW, 1, 64, 1, 0xe8b7be43 }];
    let encoded_asset_index, asset_encode_ok = format::encode_index(asset);
    assert(asset_encode_ok);
    assert_golden("tests/fixtures/v1-one-raw-entry-index.hex", encoded_asset_index);
    let asset_header = format::Header { 1, 65, 45, format::crc32(encoded_asset_index) };
    var decoded_assets: format::Entry[>..] = [];
    assert(format::decode_index(encoded_asset_index, asset_header, decoded_assets));
    assert(decoded_assets.len == 1 && decoded_assets[0].path == "a");
    var reserved_index: u8[>..] = [];
    reserved_index.append(encoded_asset_index);
    reserved_index[9] = 1;
    let reserved_header = format::Header { 1, 65, 45, format::crc32(reserved_index) };
    assert(!format::decode_index(reserved_index, reserved_header, decoded_assets));
    var trailing_index: u8[>..] = [];
    trailing_index.append(encoded_asset_index);
    trailing_index.append([0]);
    let trailing_header = format::Header { 1, 65, 46, format::crc32(trailing_index) };
    assert(!format::decode_index(trailing_index, trailing_header, decoded_assets));
    var overlapping: format::Entry[2] = [
        format::Entry { "a", format::RAW, 1, 64, 1, 0 },
        format::Entry { "b", format::RAW, 1, 64, 1, 0 },
    ];
    assert(!format::validate_entries(overlapping, 65));
    let bad_codec: format::Entry[1] = [format::Entry { "a", 2, 1, 64, 1, 0 }];
    assert(!format::validate_entries(bad_codec, 65));
    let out_of_range: format::Entry[1] = [format::Entry { "a", format::RAW, 1, 65, 1, 0 }];
    assert(!format::validate_entries(out_of_range, 65));
    let duplicate_paths: format::Entry[2] = [
        format::Entry { "a", format::RAW, 0, 64, 0, 0 },
        format::Entry { "a", format::RAW, 0, 64, 0, 0 },
    ];
    assert(!format::validate_entries(duplicate_paths, 65));
    let unsorted_paths: format::Entry[2] = [
        format::Entry { "b", format::RAW, 0, 64, 0, 0 },
        format::Entry { "a", format::RAW, 0, 64, 0, 0 },
    ];
    assert(!format::validate_entries(unsorted_paths, 65));
    let empty_zstd: format::Entry[1] = [format::Entry { "a", format::ZSTD, 0, 64, 0, 0 }];
    assert(!format::validate_entries(empty_zstd, 65));
    let empty_bad_crc: format::Entry[1] = [format::Entry { "a", format::RAW, 0, 64, 0, 1 }];
    assert(!format::validate_entries(empty_bad_crc, 65));
    let zero_stored: format::Entry[1] = [format::Entry { "a", format::ZSTD, 10, 64, 0, 0 }];
    assert(!format::validate_entries(zero_stored, 65));
}
