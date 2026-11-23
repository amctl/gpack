#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zstd.h>

typedef struct { uint8_t *data; int64_t len; } sl_u8;

int32_t h3_reader_open(sl_u8 path) {
    char *name = malloc((size_t)path.len + 1);
    if (!name) return -1;
    memcpy(name, path.data, (size_t)path.len);
    name[path.len] = 0;
    int fd = open(name, O_RDONLY | O_CLOEXEC);
    free(name);
    return fd;
}

int64_t h3_reader_size(int32_t fd) {
    struct stat st;
    if (fstat(fd, &st) || st.st_size < 0) return -1;
    return (int64_t)st.st_size;
}

int64_t h3_reader_read_at(int32_t fd, int64_t offset, sl_u8 output) {
    if (offset < 0 || output.len < 0 || (uint64_t)offset > INT64_MAX - (uint64_t)output.len) return -1;
    size_t done = 0;
    while (done < (size_t)output.len) {
        ssize_t n = pread(fd, output.data + done, (size_t)output.len - done, (off_t)(offset + (int64_t)done));
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        done += (size_t)n;
    }
    return (int64_t)done;
}

int32_t h3_reader_close(int32_t fd) { return close(fd); }

int64_t h3_reader_decompress(sl_u8 input, sl_u8 output) {
    size_t frame = ZSTD_findFrameCompressedSize(input.data, (size_t)input.len);
    if (ZSTD_isError(frame) || frame != (size_t)input.len) return -1;
    size_t size = ZSTD_decompress(output.data, (size_t)output.len, input.data, (size_t)input.len);
    if (ZSTD_isError(size)) return -1;
    return (int64_t)size;
}
