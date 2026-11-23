#ifndef GPACK_H3_BACKEND_H
#define GPACK_H3_BACKEND_H

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <zstd.h>

static FILE *h3_output;
static char *h3_final_path;
static char *h3_temp_path;
static unsigned long long h3_written;
static unsigned long long h3_fail_after = ~0ULL;
static size_t h3_read_limit;
static size_t h3_write_limit;

static bool h3_write_all(const void *data, size_t size) {
    const unsigned char *bytes = data;
    while (size) {
        if (h3_written >= h3_fail_after) return false;
        size_t amount = size;
        if (h3_write_limit && amount > h3_write_limit) amount = h3_write_limit;
        if (h3_fail_after - h3_written < amount) amount = (size_t)(h3_fail_after - h3_written);
        if (!amount) return false;
        size_t done = fwrite(bytes, 1, amount, h3_output);
        if (!done) return false;
        bytes += done;
        size -= done;
        h3_written += done;
    }
    return true;
}

uint8_t h3_begin(sl_u8 path) {
    if (h3_output) return false;
    const char *limit = getenv("GPACK_H3_FAIL_AFTER");
    h3_fail_after = limit ? strtoull(limit, NULL, 10) : ~0ULL;
    const char *short_read = getenv("GPACK_H3_SHORT_READ");
    const char *short_write = getenv("GPACK_H3_SHORT_WRITE");
    h3_read_limit = short_read ? (size_t)strtoull(short_read, NULL, 10) : 0;
    h3_write_limit = short_write ? (size_t)strtoull(short_write, NULL, 10) : 0;
    h3_final_path = malloc((size_t)path.len + 1);
    h3_temp_path = malloc((size_t)path.len + 5);
    if (!h3_final_path || !h3_temp_path) return false;
    memcpy(h3_final_path, path.data, (size_t)path.len);
    h3_final_path[path.len] = 0;
    memcpy(h3_temp_path, path.data, (size_t)path.len);
    memcpy(h3_temp_path + path.len, ".tmp", 5);
    h3_output = fopen(h3_temp_path, "wb");
    if (!h3_output) return false;
    h3_written = 0;
    return true;
}

uint8_t h3_write(sl_u8 data) {
    return h3_output && h3_write_all(data.data, (size_t)data.len);
}

uint8_t h3_compress_file(sl_u8 path) {
    char *name = malloc((size_t)path.len + 1);
    if (!name) return false;
    memcpy(name, path.data, (size_t)path.len);
    name[path.len] = 0;
    FILE *input = fopen(name, "rb");
    free(name);
    if (!input) return false;
    ZSTD_CCtx *ctx = ZSTD_createCCtx();
    if (!ctx) { fclose(input); return false; }
    size_t rc = ZSTD_CCtx_setParameter(ctx, ZSTD_c_compressionLevel, 3);
    if (ZSTD_isError(rc)) { ZSTD_freeCCtx(ctx); fclose(input); return false; }
    unsigned char in[131072], out[131072];
    bool ok = true;
    for (;;) {
        size_t cap = h3_read_limit && h3_read_limit < sizeof(in) ? h3_read_limit : sizeof(in);
        size_t got = fread(in, 1, cap, input);
        bool eof = feof(input);
        if (ferror(input)) { ok = false; break; }
        ZSTD_inBuffer src = { in, got, 0 };
        ZSTD_EndDirective directive = eof ? ZSTD_e_end : ZSTD_e_continue;
        size_t remaining;
        do {
            ZSTD_outBuffer dst = { out, sizeof(out), 0 };
            remaining = ZSTD_compressStream2(ctx, &dst, &src, directive);
            if (ZSTD_isError(remaining) || !h3_write_all(out, dst.pos)) { ok = false; break; }
        } while (src.pos < src.size || (eof && remaining != 0));
        if (!ok || eof) break;
    }
    ZSTD_freeCCtx(ctx);
    fclose(input);
    return ok;
}

uint8_t h3_finish(void) {
    if (!h3_output) return false;
    bool ok = fflush(h3_output) == 0 && fsync(fileno(h3_output)) == 0;
    if (fclose(h3_output) != 0) ok = false;
    h3_output = NULL;
    if (ok && rename(h3_temp_path, h3_final_path) != 0) ok = false;
    if (!ok) remove(h3_temp_path);
    free(h3_final_path); free(h3_temp_path);
    h3_final_path = h3_temp_path = NULL;
    return ok;
}

void h3_abort(void) {
    if (h3_output) fclose(h3_output);
    h3_output = NULL;
    if (h3_temp_path) remove(h3_temp_path);
    free(h3_final_path); free(h3_temp_path);
    h3_final_path = h3_temp_path = NULL;
}

int64_t h3_compress_bytes(sl_u8 input, sl_u8 output) {
    ZSTD_CCtx *ctx = ZSTD_createCCtx();
    if (!ctx) return -1;
    size_t rc = ZSTD_CCtx_setParameter(ctx, ZSTD_c_compressionLevel, 3);
    if (ZSTD_isError(rc)) { ZSTD_freeCCtx(ctx); return -1; }
    size_t cap = 131072;
    const char *limit = getenv("GPACK_H3_SHORT_READ");
    if (limit) { size_t forced = (size_t)strtoull(limit, NULL, 10); if (forced) cap = forced; }
    unsigned char encoded[131072];
    size_t offset = 0, written = 0;
    bool done = false, ok = true;
    while (!done) {
        size_t amount = (size_t)input.len - offset;
        if (amount > cap) amount = cap;
        bool eof = amount < cap;
        ZSTD_inBuffer src = { input.data ? input.data + offset : NULL, amount, 0 };
        size_t remaining;
        do {
            ZSTD_outBuffer dst = { encoded, sizeof(encoded), 0 };
            remaining = ZSTD_compressStream2(ctx, &dst, &src, eof ? ZSTD_e_end : ZSTD_e_continue);
            if (ZSTD_isError(remaining) || dst.pos > (size_t)output.len - written) { ok = false; break; }
            memcpy(output.data + written, encoded, dst.pos);
            written += dst.pos;
        } while (src.pos < src.size || (eof && remaining != 0));
        if (!ok) break;
        if (eof) done = true;
        else {
            offset += amount;
            if (amount == 0) { ok = false; break; }
        }
    }
    ZSTD_freeCCtx(ctx);
    return ok ? (int64_t)written : -1;
}

#endif
