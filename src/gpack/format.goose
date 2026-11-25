// Goose-owned field-by-field implementation of the normative v1 wire format.
namespace format;
import binary;
import std;

let HEADER_SIZE:    i64 = 64;
let MAX_ENTRIES:    u64 = 1000000;
let MAX_INDEX_SIZE: u64 = 64 * 1024 * 1024;
let MAX_ASSET_SIZE: u64 = 8 * 1024 * 1024 * 1024;
let RAW:            u8  = 0;
let ZSTD:           u8  = 1;
let CRC32_TABLE: u32[256] = [
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba,
    0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
    0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988,
    0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
    0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de,
    0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec,
    0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
    0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
    0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
    0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940,
    0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116,
    0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
    0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924,
    0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
    0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a,
    0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818,
    0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
    0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e,
    0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
    0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c,
    0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2,
    0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
    0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
    0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
    0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086,
    0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4,
    0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
    0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a,
    0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
    0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8,
    0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe,
    0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
    0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc,
    0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
    0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252,
    0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60,
    0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
    0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
    0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
    0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04,
    0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a,
    0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
    0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38,
    0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
    0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e,
    0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c,
    0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
    0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2,
    0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
    0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0,
    0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6,
    0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
    0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
    0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d,
];

struct Header { entry_count: u64, index_offset: u64, index_size: u64, index_crc32: u32 }
struct Entry {
    path:           const u8[:], codec: u8, uncompressed_size: u64,
    payload_offset: u64, stored_size: u64, content_crc32: u32,
}

fn crc32_update(state: u32, data: const u8[:]) -> u32 {
    var crc = state;
    for byte in data {
        crc = CRC32_TABLE[((crc ^ byte) & 0xff) as i64] ^ (crc >> 8);
    }
    return crc;
}

fn crc32(data: const u8[:]) -> u32 {
    return ~crc32_update(0xffffffff, data);
}

fn crc32_header(data: const u8[:]) -> u32 {
    if data.len != HEADER_SIZE { return 0; }
    let zero_crc: u8[4] = [0, 0, 0, 0];
    var crc = crc32_update(0xffffffff, data[..44]);
    crc = crc32_update(crc, zero_crc);
    crc = crc32_update(crc, data[48..HEADER_SIZE]);
    return ~crc;
}

fn encode_header(header: Header) -> u8[>..] {
    var out: u8[>..] = [];
    out.append("GPKARCH\0");
    binary::write_u16le(out, 1); binary::write_u16le(out, 0); binary::write_u32le(out, HEADER_SIZE as u32);
    binary::write_u64le(out, header.entry_count); binary::write_u64le(out, header.index_offset);
    binary::write_u64le(out, header.index_size); binary::write_u32le(out, header.index_crc32);
    binary::write_u32le(out, 0);
    for _ in 0..16 { binary::write_u8(out, 0); }
    let checksum = crc32_header(out);
    for i in 0..4 { out[44 + i] = (checksum >> (i * 8)) as u8; }
    return out;
}

fn decode_header(data: const u8[:], file_size: u64) -> Header, bool {
    let empty = Header { 0, 0, 0, 0 };
    if data.len != HEADER_SIZE || data[0..8] != "GPKARCH\0" { return empty, false; }
    if binary::u16le(data, 8) != 1 || binary::u16le(data, 10) != 0 || binary::u32le(data, 12) != 64 { return empty, false; }
    if binary::u32le(data, 44) != crc32_header(data) { return empty, false; }
    for i in 48..64 { if data[i] != 0 { return empty, false; } }
    let count = binary::u64le(data, 16);
    let offset = binary::u64le(data, 24);
    let size = binary::u64le(data, 32);
    if count > MAX_ENTRIES || size < 4 || size > MAX_INDEX_SIZE { return empty, false; }
    if offset < 64 || offset > file_size || size != file_size - offset { return empty, false; }
    return Header { count, offset, size, binary::u32le(data, 40) }, true;
}

fn valid_utf8(data: const u8[:]) -> bool {
    var i = 0;
    while i < data.len {
        let a = data[i];
        if a < 0x80 { i++; continue; }
        var n = 0;
        if a >= 0xc2 && a <= 0xdf { n = 2; }
        else if a >= 0xe0 && a <= 0xef { n = 3; }
        else if a >= 0xf0 && a <= 0xf4 { n = 4; }
        else { return false; }
        if i + n > data.len { return false; }
        for j in 1..n { if data[i + j] < 0x80 || data[i + j] > 0xbf { return false; } }
        if n == 3 && ((a == 0xe0 && data[i + 1] < 0xa0) || (a == 0xed && data[i + 1] >= 0xa0)) { return false; }
        if n == 4 && ((a == 0xf0 && data[i + 1] < 0x90) || (a == 0xf4 && data[i + 1] >= 0x90)) { return false; }
        i += n;
    }
    return true;
}

fn valid_path(path: const u8[:]) -> bool {
    if path.len == 0 || path.len > 4096 || !valid_utf8(path) || path[0] == '/' { return false; }
    var component = 0;
    for i in 0..path.len {
        let c = path[i];
        if c == 0 || c == '\\' { return false; }
        if c == '/' {
            if i == component || (i - component == 1 && path[component] == '.') || (i - component == 2 && path[component] == '.' && path[component + 1] == '.') { return false; }
            component = i + 1;
        }
    }
    if component == path.len || (path.len - component == 1 && path[component] == '.') || (path.len - component == 2 && path[component] == '.' && path[component + 1] == '.') { return false; }
    return true;
}

fn path_less(a: const u8[:], b: const u8[:]) -> bool {
    let n = min(a.len, b.len);
    for i in 0..n { if a[i] != b[i] { return a[i] < b[i]; } }
    return a.len < b.len;
}

fn encode_index(entries: const Entry[:]) -> u8[>..], bool {
    if entries.len > MAX_ENTRIES || !validate_entries(entries, 0xffffffffffffffff) { return [], false; }
    var encoded_size: u64 = 4;
    for entry in entries {
        let record_size = 40 + entry.path.len as u64;
        if record_size > MAX_INDEX_SIZE - encoded_size { return [], false; }
        encoded_size += record_size;
    }
    var out: u8[>..] = [];
    binary::write_u32le(out, entries.len as u32);
    for entry in entries {
        binary::write_u32le(out, entry.path.len as u32);
        binary::write_u8(out, entry.codec); binary::write_u8(out, 0); binary::write_u8(out, 0); binary::write_u8(out, 0);
        binary::write_u64le(out, entry.uncompressed_size); binary::write_u64le(out, entry.payload_offset);
        binary::write_u64le(out, entry.stored_size); binary::write_u32le(out, entry.content_crc32); binary::write_u32le(out, 0);
        out.append(entry.path);
    }
    return out, true;
}

fn decode_index(data: const u8[:], header: Header, entries: Entry[>..]&) -> bool {
    if header.index_size < 4 || header.index_size > MAX_INDEX_SIZE || data.len < 4 || data.len as u64 != header.index_size || crc32(data) != header.index_crc32 { return false; }
    let count = binary::u32le(data, 0) as u64;
    if count != header.entry_count || count > MAX_ENTRIES { return false; }
    entries.clear();
    var at: i64 = 4;
    for _ in 0..count {
        if at > data.len || data.len - at < 40 { entries.clear(); return false; }
        let path_len = binary::u32le(data, at) as u64;
        let codec = data[at + 4];
        if path_len == 0 || path_len > 4096 { entries.clear(); return false; }
        if data[at + 5] != 0 || data[at + 6] != 0 || data[at + 7] != 0 || binary::u32le(data, at + 36) != 0 { entries.clear(); return false; }
        let uncompressed = binary::u64le(data, at + 8);
        let offset = binary::u64le(data, at + 16);
        let stored = binary::u64le(data, at + 24);
        let content_crc = binary::u32le(data, at + 32);
        at += 40;
        if path_len > (data.len - at) as u64 { entries.clear(); return false; }
        let path = data[at..at + path_len as i64];
        at += path_len as i64;
        let entry: Entry[1] = [Entry { path, codec, uncompressed, offset, stored, content_crc }];
        entries.append(entry);
    }
    if at != data.len || !validate_entries(entries, header.index_offset) { entries.clear(); return false; }
    return true;
}

fn validate_entries(entries: const Entry[:], index_offset: u64) -> bool {
    if entries.len > MAX_ENTRIES { return false; }
    var previous_end: u64 = 64;
    for i in 0..entries.len {
        let e = entries[i];
        if !valid_path(e.path) || e.uncompressed_size > MAX_ASSET_SIZE { return false; }
        if i > 0 && !path_less(entries[i - 1].path, e.path) { return false; }
        if e.codec == RAW {
            if e.stored_size != e.uncompressed_size { return false; }
        } else if e.codec != ZSTD { return false; }
        if e.uncompressed_size == 0 {
            if e.codec != RAW || e.stored_size != 0 || e.content_crc32 != 0 || e.payload_offset < 64 || e.payload_offset > index_offset { return false; }
            continue;
        }
        if e.stored_size == 0 { return false; }
        if e.payload_offset < 64 || e.payload_offset > index_offset || e.stored_size > index_offset - e.payload_offset { return false; }
        if e.payload_offset < previous_end { return false; }
        previous_end = e.payload_offset + e.stored_size;
    }
    return true;
}
