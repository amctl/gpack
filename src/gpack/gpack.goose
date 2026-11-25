namespace gpack;

let VERSION:      const u8[:] = "1.0.0";
let FORMAT_MAJOR: u16         = 1;
let FORMAT_MINOR: u16         = 0;

extern fn gpack_native_abi_probe(value: u64) -> u64 = "gpack_native_abi_probe";
extern fn gpack_native_zstd_version() -> u32 = "gpack_native_zstd_version";

fn zstd_version() -> u32 {
    return gpack_native_zstd_version();
}
extern fn native_file_open_read(path: const u8[:]) -> u64 = "gpack_file_open_read";
extern fn native_file_open_write(path: const u8[:]) -> u64 = "gpack_file_open_write";
extern fn native_file_open_exclusive(path: const u8[:]) -> u64 = "gpack_file_open_exclusive";
extern fn native_temp_nonce() -> u64 = "gpack_temp_nonce";
extern fn native_file_replace(source: const u8[:], destination: const u8[:]) -> i32 = "gpack_file_replace";
extern fn native_file_remove(path: const u8[:]) -> i32 = "gpack_file_remove";
extern fn native_path_kind(path: const u8[:]) -> i32 = "gpack_path_kind";
extern fn native_file_size(handle: u64) -> u64 = "gpack_file_size";
extern fn native_file_stamp(handle: u64) -> u64 = "gpack_file_stamp";
extern fn native_file_read_at(handle: u64, offset: u64, output: u8[:]) -> i64 = "gpack_file_read_at";
extern fn native_file_write_at(handle: u64, offset: u64, input: const u8[:]) -> i64 = "gpack_file_write_at";
extern fn native_file_flush(handle: u64) -> i32 = "gpack_file_flush";
extern fn native_file_close(handle: u64) = "gpack_file_close";
extern fn native_zstd_compress_begin(source_size: u64) -> u64 = "gpack_zstd_compress_begin";
extern fn native_zstd_compress_step(context: u64, input: const u8[:], output: u8[:], finish: bool) -> u64 = "gpack_zstd_compress_step";
extern fn native_zstd_compress_end(context: u64) = "gpack_zstd_compress_end";
extern fn native_zstd_decompress_begin(max_window_log: i32) -> u64 = "gpack_zstd_decompress_begin";
extern fn native_zstd_decompress_step(context: u64, input: const u8[:], output: u8[:]) -> u64 = "gpack_zstd_decompress_step";
extern fn native_zstd_decompress_end(context: u64) = "gpack_zstd_decompress_end";
extern fn native_zstd_decompress_one_shot(input: const u8[:], output: u8[:], max_window_log: i32) -> i32 = "gpack_zstd_decompress_one_shot";
