#ifndef GPACK_NATIVE_H
#define GPACK_NATIVE_H

#include <stdint.h>
#include <stddef.h>

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define GPACK_STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)
#elif defined(__cplusplus)
#define GPACK_STATIC_ASSERT(cond, msg) static_assert(cond, msg)
#else
#define GPACK_STATIC_ASSERT(cond, msg) typedef char gpack_static_assert_##__LINE__[(cond) ? 1 : -1]
#endif

#ifdef GPACK_NATIVE_IMPL
typedef struct { uint8_t *data; int64_t len; } gpack_bytes;
#else
typedef sl_u8 gpack_bytes;
GPACK_STATIC_ASSERT(sizeof(gpack_bytes) == sizeof(sl_u8), "Goose byte-slice ABI mismatch");
#endif

#if defined(GPACK_NATIVE_IMPL)
GPACK_STATIC_ASSERT(offsetof(gpack_bytes, len) == sizeof(uint8_t *), "native byte-slice field offset mismatch");
GPACK_STATIC_ASSERT(sizeof(gpack_bytes) == sizeof(uint8_t *) + sizeof(int64_t), "native byte-slice size mismatch");
#endif

#ifdef __cplusplus
extern "C" {
#endif

uint64_t gpack_native_abi_probe(uint64_t value);
uint32_t gpack_native_zstd_version(void);
uint64_t gpack_file_open_read(gpack_bytes path);
uint64_t gpack_file_open_write(gpack_bytes path);
uint64_t gpack_file_open_exclusive(gpack_bytes path);
uint64_t gpack_temp_nonce(void);
int32_t gpack_file_replace(gpack_bytes source, gpack_bytes destination);
int32_t gpack_file_remove(gpack_bytes path);
int32_t gpack_path_kind(gpack_bytes path);
uint64_t gpack_file_size(uint64_t handle);
uint64_t gpack_file_stamp(uint64_t handle);
int64_t gpack_file_read_at(uint64_t handle, uint64_t offset, gpack_bytes output);
int64_t gpack_file_write_at(uint64_t handle, uint64_t offset, gpack_bytes input);
int32_t gpack_file_flush(uint64_t handle);
void gpack_file_close(uint64_t handle);
int32_t gpack_write_stdout(gpack_bytes data);
uint64_t gpack_zstd_compress_begin(uint64_t source_size);
uint64_t gpack_zstd_compress_step(uint64_t context, gpack_bytes input, gpack_bytes output, uint8_t finish);
void gpack_zstd_compress_end(uint64_t context);
uint64_t gpack_zstd_decompress_begin(int32_t max_window_log);
uint64_t gpack_zstd_decompress_step(uint64_t context, gpack_bytes input, gpack_bytes output);
void gpack_zstd_decompress_end(uint64_t context);
int32_t gpack_zstd_decompress_one_shot(gpack_bytes input, gpack_bytes output, int32_t max_window_log);

#ifdef __cplusplus
}
#endif

#endif
