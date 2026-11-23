#define GPACK_NATIVE_IMPL
#include "gpack_native.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <zlib.h>

typedef struct { z_stream stream; } zip_inflate_context;
typedef struct { z_stream stream; } zip_deflate_context;

static uint64_t zip_result(size_t consumed, size_t produced, int done) {
    if (consumed > 0x7fffffffU || produced > 0x7fffffffU) return UINT64_MAX;
    uint64_t result = ((uint64_t)consumed << 32) | (uint64_t)produced;
    if (done) result |= UINT64_C(0x8000000000000000);
    return result;
}

uint64_t zip_deflate_begin(int32_t level) {
    zip_deflate_context *context = (zip_deflate_context *)calloc(1, sizeof(*context));
    if (context == NULL) return 0;
    if (deflateInit2(&context->stream, level, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        free(context);
        return 0;
    }
    return (uint64_t)(uintptr_t)context;
}

uint64_t zip_deflate_step(uint64_t handle, gpack_bytes input, gpack_bytes output, uint8_t finish) {
    zip_deflate_context *context = (zip_deflate_context *)(uintptr_t)handle;
    if (context == NULL || input.len < 0 || output.len < 0 ||
        input.len > UINT_MAX || output.len > UINT_MAX) return UINT64_MAX;
    context->stream.next_in = input.data;
    context->stream.avail_in = (uInt)input.len;
    context->stream.next_out = output.data;
    context->stream.avail_out = (uInt)output.len;
    int status = deflate(&context->stream, finish ? Z_FINISH : Z_NO_FLUSH);
    size_t consumed = (size_t)input.len - context->stream.avail_in;
    size_t produced = (size_t)output.len - context->stream.avail_out;
    if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) return UINT64_MAX;
    return zip_result(consumed, produced, status == Z_STREAM_END);
}

void zip_deflate_end(uint64_t handle) {
    zip_deflate_context *context = (zip_deflate_context *)(uintptr_t)handle;
    if (context == NULL) return;
    deflateEnd(&context->stream);
    free(context);
}

uint64_t zip_inflate_begin(void) {
    zip_inflate_context *context = (zip_inflate_context *)calloc(1, sizeof(*context));
    if (context == NULL) return 0;
    if (inflateInit2(&context->stream, -MAX_WBITS) != Z_OK) {
        free(context);
        return 0;
    }
    return (uint64_t)(uintptr_t)context;
}

uint64_t zip_inflate_step(uint64_t handle, gpack_bytes input, gpack_bytes output) {
    zip_inflate_context *context = (zip_inflate_context *)(uintptr_t)handle;
    if (context == NULL || input.len < 0 || output.len < 0 ||
        input.len > UINT_MAX || output.len > UINT_MAX) return UINT64_MAX;

    context->stream.next_in = input.data;
    context->stream.avail_in = (uInt)input.len;
    context->stream.next_out = output.data;
    context->stream.avail_out = (uInt)output.len;
    int status = inflate(&context->stream, Z_NO_FLUSH);
    size_t consumed = (size_t)input.len - context->stream.avail_in;
    size_t produced = (size_t)output.len - context->stream.avail_out;
    if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) return UINT64_MAX;
    return zip_result(consumed, produced, status == Z_STREAM_END);
}

void zip_inflate_end(uint64_t handle) {
    zip_inflate_context *context = (zip_inflate_context *)(uintptr_t)handle;
    if (context == NULL) return;
    inflateEnd(&context->stream);
    free(context);
}
