#if !defined(_WIN32) && !defined(__APPLE__)
#define _POSIX_C_SOURCE 200809L
#endif
#define GPACK_NATIVE_IMPL 1
#include "gpack_native.h"
#include <zstd.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GPACK_IO_CHUNK (64U * 1024U * 1024U)

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <fcntl.h>
#include <io.h>
#include <windows.h>
static HANDLE gpack_handle(uint64_t value) { return (HANDLE)(uintptr_t)value; }
static uint64_t gpack_id(HANDLE value) { return (uint64_t)(uintptr_t)value; }

static wchar_t *gpack_wide_path(gpack_bytes path) {
    if (path.len <= 0 || path.len > INT_MAX || memchr(path.data, 0, (size_t)path.len)) return NULL;
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path.data, (int)path.len, NULL, 0);
    if (count <= 0) return NULL;
    wchar_t *wide = (wchar_t *)malloc(((size_t)count + 1) * sizeof(wchar_t));
    if (!wide) return NULL;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path.data, (int)path.len, wide, count) != count) {
        free(wide); return NULL;
    }
    wide[count] = L'\0';
    return wide;
}

uint64_t gpack_file_open_read(gpack_bytes path) {
    wchar_t *wide = gpack_wide_path(path);
    if (!wide) return 0;
    HANDLE h = CreateFileW(wide, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                           FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    free(wide);
    if (h == INVALID_HANDLE_VALUE) return 0;
    BY_HANDLE_FILE_INFORMATION info;
    if (!GetFileInformationByHandle(h, &info) || (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) {
        CloseHandle(h); return 0;
    }
    return gpack_id(h);
}

int32_t gpack_path_kind(gpack_bytes path) {
    wchar_t *wide = gpack_wide_path(path);
    if (!wide) return 0;
    HANDLE h = CreateFileW(wide, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    free(wide);
    if (h == INVALID_HANDLE_VALUE) return 0;
    BY_HANDLE_FILE_INFORMATION info;
    int32_t kind = 0;
    if (GetFileInformationByHandle(h, &info) && !(info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT))
        kind = (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 2 : 1;
    CloseHandle(h);
    return kind;
}

static volatile LONG64 gpack_temp_counter = 0;
uint64_t gpack_temp_nonce(void) {
    return ((uint64_t)GetCurrentProcessId() << 32) |
           (uint32_t)InterlockedIncrement64(&gpack_temp_counter);
}

uint64_t gpack_file_open_exclusive(gpack_bytes path) {
    wchar_t *wide = gpack_wide_path(path);
    if (!wide) return 0;
    HANDLE h = CreateFileW(wide, GENERIC_WRITE, 0, NULL, CREATE_NEW,
                           FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED, NULL);
    free(wide);
    return h == INVALID_HANDLE_VALUE ? 0 : gpack_id(h);
}

int32_t gpack_file_replace(gpack_bytes source, gpack_bytes destination) {
    wchar_t *from = gpack_wide_path(source);
    wchar_t *to = gpack_wide_path(destination);
    if (!from || !to) { free(from); free(to); return 0; }
    int32_t ok = MoveFileExW(from, to, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) ? 1 : 0;
    free(from); free(to);
    return ok;
}

int32_t gpack_file_remove(gpack_bytes path) {
    wchar_t *wide = gpack_wide_path(path);
    if (!wide) return 0;
    int32_t ok = DeleteFileW(wide) ? 1 : 0;
    free(wide);
    return ok;
}

uint64_t gpack_file_size(uint64_t handle) {
    LARGE_INTEGER size;
    return GetFileSizeEx(gpack_handle(handle), &size) && size.QuadPart >= 0 ? (uint64_t)size.QuadPart : UINT64_MAX;
}

uint64_t gpack_file_stamp(uint64_t handle) {
    FILETIME modified;
    if (!GetFileTime(gpack_handle(handle), NULL, NULL, &modified)) return UINT64_MAX;
    return ((uint64_t)modified.dwHighDateTime << 32) | modified.dwLowDateTime;
}

static int64_t gpack_transfer(uint64_t handle, uint64_t offset, gpack_bytes bytes, int write_mode) {
    if (bytes.len < 0 || offset > INT64_MAX) return -1;
    HANDLE ev = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!ev) return -1;
    int64_t done = 0;
    while (done < bytes.len) {
        uint64_t remaining = (uint64_t)(bytes.len - done);
        DWORD amount = remaining > GPACK_IO_CHUNK ? (DWORD)GPACK_IO_CHUNK : (DWORD)remaining;
        OVERLAPPED ov;
        memset(&ov, 0, sizeof(ov));
        ResetEvent(ev);
        ov.hEvent = ev;
        uint64_t position = offset + (uint64_t)done;
        if (position > INT64_MAX) { CloseHandle(ev); return -1; }
        ov.Offset = (DWORD)position;
        ov.OffsetHigh = (DWORD)(position >> 32);
        DWORD transferred = 0;
        BOOL ok = write_mode
            ? WriteFile(gpack_handle(handle), bytes.data + (size_t)done, amount, &transferred, &ov)
            : ReadFile(gpack_handle(handle), bytes.data + (size_t)done, amount, &transferred, &ov);
        if (!ok && GetLastError() == ERROR_IO_PENDING)
            ok = GetOverlappedResult(gpack_handle(handle), &ov, &transferred, TRUE);
        if (!ok) { CloseHandle(ev); return done == 0 ? -1 : done; }
        if (transferred == 0) break;
        done += transferred;
        if (!write_mode && transferred < amount) break;
    }
    CloseHandle(ev);
    return done;
}

int64_t gpack_file_read_at(uint64_t h, uint64_t off, gpack_bytes out) { return gpack_transfer(h, off, out, 0); }
int64_t gpack_file_write_at(uint64_t h, uint64_t off, gpack_bytes in) { return gpack_transfer(h, off, in, 1); }
int32_t gpack_file_flush(uint64_t h) { return FlushFileBuffers(gpack_handle(h)) ? 1 : 0; }
void gpack_file_close(uint64_t h) { if (h) CloseHandle(gpack_handle(h)); }

#else
#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int gpack_fd(uint64_t handle) { return handle == 0 || handle - 1 > INT_MAX ? -1 : (int)(handle - 1); }

static int gpack_path_fd(gpack_bytes path) {
    if (path.len <= 0 || (uint64_t)path.len > SIZE_MAX - 1 || memchr(path.data, 0, (size_t)path.len)) return -1;
    char *text = (char *)malloc((size_t)path.len + 1);
    if (!text) return -1;
    memcpy(text, path.data, (size_t)path.len);
    text[path.len] = '\0';
    int fd = open(text, O_RDONLY | O_CLOEXEC
#ifdef O_NOFOLLOW
                  | O_NOFOLLOW
#endif
    );
    free(text);
    return fd;
}

int32_t gpack_path_kind(gpack_bytes path) {
    if (path.len <= 0 || (uint64_t)path.len > SIZE_MAX - 1 || memchr(path.data, 0, (size_t)path.len)) return 0;
    char *text = (char *)malloc((size_t)path.len + 1);
    if (!text) return 0;
    memcpy(text, path.data, (size_t)path.len);
    text[path.len] = '\0';
    struct stat info;
    int result = lstat(text, &info);
    free(text);
    if (result != 0) return 0;
    if (S_ISREG(info.st_mode)) return 1;
    if (S_ISDIR(info.st_mode)) return 2;
    return 0;
}

static _Atomic uint32_t gpack_temp_counter = 0;
uint64_t gpack_temp_nonce(void) {
    uint64_t process = (uint64_t)(uint32_t)getpid();
    uint64_t counter = (uint64_t)atomic_fetch_add(&gpack_temp_counter, 1);
    return (process << 32) | counter;
}

static char *gpack_path_text(gpack_bytes path) {
    if (path.len <= 0 || (uint64_t)path.len > SIZE_MAX - 1 || memchr(path.data, 0, (size_t)path.len)) return NULL;
    char *text = (char *)malloc((size_t)path.len + 1);
    if (!text) return NULL;
    memcpy(text, path.data, (size_t)path.len);
    text[path.len] = '\0';
    return text;
}

uint64_t gpack_file_open_exclusive(gpack_bytes path) {
    char *text = gpack_path_text(path);
    if (!text) return 0;
    int fd = open(text, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0666);
    free(text);
    return fd < 0 ? 0 : (uint64_t)fd + 1;
}

int32_t gpack_file_replace(gpack_bytes source, gpack_bytes destination) {
    char *from = gpack_path_text(source);
    char *to = gpack_path_text(destination);
    if (!from || !to) { free(from); free(to); return 0; }
    int32_t ok = rename(from, to) == 0;
    free(from); free(to);
    return ok;
}

int32_t gpack_file_remove(gpack_bytes path) {
    char *text = gpack_path_text(path);
    if (!text) return 0;
    int32_t ok = unlink(text) == 0;
    free(text);
    return ok;
}

uint64_t gpack_file_open_read(gpack_bytes path) {
    int fd = gpack_path_fd(path);
    if (fd < 0) return 0;
    struct stat info;
    if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode)) { close(fd); return 0; }
    return (uint64_t)fd + 1;
}

uint64_t gpack_file_size(uint64_t handle) {
    struct stat info;
    int fd = gpack_fd(handle);
    return fd >= 0 && fstat(fd, &info) == 0 && info.st_size >= 0 ? (uint64_t)info.st_size : UINT64_MAX;
}

uint64_t gpack_file_stamp(uint64_t handle) {
    struct stat info;
    int fd = gpack_fd(handle);
    if (fd < 0 || fstat(fd, &info) != 0) return UINT64_MAX;
#if defined(__APPLE__)
    if (info.st_mtimespec.tv_sec < 0) return UINT64_MAX;
    return (uint64_t)info.st_mtimespec.tv_sec * 1000000000ULL + (uint64_t)info.st_mtimespec.tv_nsec;
#else
    if (info.st_mtim.tv_sec < 0) return UINT64_MAX;
    return (uint64_t)info.st_mtim.tv_sec * 1000000000ULL + (uint64_t)info.st_mtim.tv_nsec;
#endif
}

static int64_t gpack_transfer(uint64_t handle, uint64_t offset, gpack_bytes bytes, int write_mode) {
    int fd = gpack_fd(handle);
    if (fd < 0 || bytes.len < 0 || offset > INT64_MAX) return -1;
    int64_t done = 0;
    while (done < bytes.len) {
        uint64_t position = offset + (uint64_t)done;
        if (position > INT64_MAX) return -1;
        uint64_t remaining = (uint64_t)(bytes.len - done);
        size_t amount = remaining > GPACK_IO_CHUNK ? (size_t)GPACK_IO_CHUNK : (size_t)remaining;
        ssize_t n = write_mode
            ? pwrite(fd, bytes.data + done, amount, (off_t)position)
            : pread(fd, bytes.data + done, amount, (off_t)position);
        if (n < 0) {
            if (errno == EINTR) continue;
            return done == 0 ? -1 : done;
        }
        if (n == 0) break;
        done += n;
    }
    return done;
}

int64_t gpack_file_read_at(uint64_t h, uint64_t off, gpack_bytes out) { return gpack_transfer(h, off, out, 0); }
int64_t gpack_file_write_at(uint64_t h, uint64_t off, gpack_bytes in) { return gpack_transfer(h, off, in, 1); }
int32_t gpack_file_flush(uint64_t h) { int fd = gpack_fd(h); return fd >= 0 && fsync(fd) == 0; }
void gpack_file_close(uint64_t h) { int fd = gpack_fd(h); if (fd >= 0) close(fd); }
#endif

static uint64_t gpack_zstd_result(size_t consumed, size_t produced, int done) {
    if (consumed > 0x7fffffffU || produced > 0x7fffffffU) return UINT64_MAX;
    return ((uint64_t)consumed << 32) | (uint64_t)produced | (done ? (1ULL << 63) : 0);
}

uint64_t gpack_zstd_compress_begin(uint64_t source_size) {
    ZSTD_CCtx *ctx = ZSTD_createCCtx();
    if (!ctx) return 0;
    size_t result = ZSTD_CCtx_setParameter(ctx, ZSTD_c_compressionLevel, 3);
    if (!ZSTD_isError(result)) result = ZSTD_CCtx_setParameter(ctx, ZSTD_c_checksumFlag, 1);
    if (!ZSTD_isError(result)) result = ZSTD_CCtx_setParameter(ctx, ZSTD_c_contentSizeFlag, 1);
    if (!ZSTD_isError(result)) result = ZSTD_CCtx_setPledgedSrcSize(ctx, source_size);
    if (ZSTD_isError(result)) { ZSTD_freeCCtx(ctx); return 0; }
    return (uint64_t)(uintptr_t)ctx;
}

uint64_t gpack_zstd_compress_step(uint64_t context, gpack_bytes input, gpack_bytes output, uint8_t finish) {
    ZSTD_CCtx *ctx = (ZSTD_CCtx *)(uintptr_t)context;
    if (!ctx || input.len < 0 || output.len <= 0 || input.len > INT_MAX || output.len > INT_MAX) return UINT64_MAX;
    ZSTD_inBuffer source = { input.data, (size_t)input.len, 0 };
    ZSTD_outBuffer destination = { output.data, (size_t)output.len, 0 };
    size_t remaining = ZSTD_compressStream2(ctx, &destination, &source, finish ? ZSTD_e_end : ZSTD_e_continue);
    if (ZSTD_isError(remaining)) return UINT64_MAX;
    return gpack_zstd_result(source.pos, destination.pos, finish && remaining == 0);
}

void gpack_zstd_compress_end(uint64_t context) {
    if (context) ZSTD_freeCCtx((ZSTD_CCtx *)(uintptr_t)context);
}

uint64_t gpack_zstd_decompress_begin(int32_t max_window_log) {
    ZSTD_DCtx *ctx = ZSTD_createDCtx();
    if (!ctx) return 0;
    ZSTD_bounds bounds = ZSTD_dParam_getBounds(ZSTD_d_windowLogMax);
    if (ZSTD_isError(bounds.error)) { ZSTD_freeDCtx(ctx); return 0; }
    if (max_window_log < bounds.lowerBound) max_window_log = bounds.lowerBound;
    if (max_window_log > bounds.upperBound) max_window_log = bounds.upperBound;
    size_t result = ZSTD_DCtx_setParameter(ctx, ZSTD_d_windowLogMax, max_window_log);
    if (ZSTD_isError(result)) { ZSTD_freeDCtx(ctx); return 0; }
    return (uint64_t)(uintptr_t)ctx;
}

uint64_t gpack_zstd_decompress_step(uint64_t context, gpack_bytes input, gpack_bytes output) {
    ZSTD_DCtx *ctx = (ZSTD_DCtx *)(uintptr_t)context;
    if (!ctx || input.len < 0 || output.len < 0 || input.len > INT_MAX || output.len > INT_MAX) return UINT64_MAX;
    ZSTD_inBuffer source = { input.data, (size_t)input.len, 0 };
    ZSTD_outBuffer destination = { output.data, (size_t)output.len, 0 };
    size_t remaining = ZSTD_decompressStream(ctx, &destination, &source);
    if (ZSTD_isError(remaining)) return UINT64_MAX;
    return gpack_zstd_result(source.pos, destination.pos, remaining == 0);
}

void gpack_zstd_decompress_end(uint64_t context) {
    if (context) ZSTD_freeDCtx((ZSTD_DCtx *)(uintptr_t)context);
}

int32_t gpack_zstd_decompress_one_shot(gpack_bytes input, gpack_bytes output, int32_t max_window_log) {
    if (input.len <= 0 || output.len < 0 || (uint64_t)input.len > SIZE_MAX ||
        (uint64_t)output.len > SIZE_MAX) return 0;
    size_t frame_size = ZSTD_findFrameCompressedSize(input.data, (size_t)input.len);
    if (ZSTD_isError(frame_size) || frame_size != (size_t)input.len) return 0;
    ZSTD_DCtx *ctx = ZSTD_createDCtx();
    if (!ctx) return 0;
    ZSTD_bounds bounds = ZSTD_dParam_getBounds(ZSTD_d_windowLogMax);
    if (ZSTD_isError(bounds.error)) { ZSTD_freeDCtx(ctx); return 0; }
    if (max_window_log < bounds.lowerBound) max_window_log = bounds.lowerBound;
    if (max_window_log > bounds.upperBound) max_window_log = bounds.upperBound;
    size_t configured = ZSTD_DCtx_setParameter(ctx, ZSTD_d_windowLogMax, max_window_log);
    size_t decoded = ZSTD_isError(configured) ? configured :
        ZSTD_decompressDCtx(ctx, output.data, (size_t)output.len, input.data, (size_t)input.len);
    ZSTD_freeDCtx(ctx);
    return !ZSTD_isError(decoded) && decoded == (size_t)output.len;
}

GPACK_STATIC_ASSERT(sizeof(uint64_t) == 8, "uint64_t ABI width must be 8 bytes");
GPACK_STATIC_ASSERT(sizeof(uint32_t) == 4, "uint32_t ABI width must be 4 bytes");

uint64_t gpack_native_abi_probe(uint64_t value) {
    return value;
}

uint32_t gpack_native_zstd_version(void) {
    return (uint32_t) ZSTD_versionNumber();
}

int32_t gpack_write_stdout(gpack_bytes data) {
    if (data.len < 0) return 0;
    if (data.len == 0) return 1;
#if defined(_WIN32)
    fflush(stdout);
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    size_t offset = 0;
    size_t total = (size_t)data.len;
    while (offset < total) {
        size_t remaining = total - offset;
        size_t chunk = remaining > GPACK_IO_CHUNK ? (size_t)GPACK_IO_CHUNK : remaining;
        size_t written = fwrite(data.data + offset, 1, chunk, stdout);
        if (written != chunk) return 0;
        offset += written;
    }
    return fflush(stdout) == 0;
}
