#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <zstd.h>

static FILE *out;
static unsigned long long written;
static unsigned long long fail_after = ~0ULL;
static size_t read_limit, write_limit;

static int write_all(const void *data, size_t size) {
    const unsigned char *p = data;
    while (size) {
        if (written >= fail_after) return 0;
        size_t n = size;
        if (write_limit && n > write_limit) n = write_limit;
        if (fail_after - written < n) n = (size_t)(fail_after - written);
        if (!n) return 0;
        size_t done = fwrite(p, 1, n, out);
        if (!done) return 0;
        p += done; size -= done; written += done;
    }
    return 1;
}

static int put_u32(uint32_t v) {
    unsigned char b[4];
    for (int i=0;i<4;i++) b[i]=(unsigned char)(v>>(8*i));
    return write_all(b, sizeof b);
}
static int put_u64(uint64_t v) {
    unsigned char b[8];
    for (int i=0;i<8;i++) b[i]=(unsigned char)(v>>(8*i));
    return write_all(b, sizeof b);
}

static int stream_frame(const char *path) {
    FILE *in=fopen(path,"rb"); if(!in) return 0;
    ZSTD_CCtx *ctx=ZSTD_createCCtx(); if(!ctx){fclose(in);return 0;}
    size_t rc=ZSTD_CCtx_setParameter(ctx,ZSTD_c_compressionLevel,3);
    if(ZSTD_isError(rc)){ZSTD_freeCCtx(ctx);fclose(in);return 0;}
    unsigned char ib[131072], ob[131072]; int ok=1;
    for(;;){
        size_t amount=read_limit&&read_limit<sizeof ib?read_limit:sizeof ib;
        size_t got=fread(ib,1,amount,in); int eof=feof(in);
        if(ferror(in)){ok=0;break;}
        ZSTD_inBuffer src={ib,got,0}; ZSTD_EndDirective mode=eof?ZSTD_e_end:ZSTD_e_continue;
        size_t remaining;
        do {
            ZSTD_outBuffer dst={ob,sizeof ob,0};
            remaining=ZSTD_compressStream2(ctx,&dst,&src,mode);
            if(ZSTD_isError(remaining)||!write_all(ob,dst.pos)){ok=0;break;}
        } while(src.pos<src.size||(eof&&remaining!=0));
        if(!ok||eof)break;
    }
    ZSTD_freeCCtx(ctx);fclose(in);return ok;
}

int main(int argc,char **argv){
    if(argc!=3){fprintf(stderr,"usage: c_reference MANIFEST OUTPUT\n");return 2;}
    const char *failure=getenv("GPACK_H3_FAIL_AFTER");
    if(failure)fail_after=strtoull(failure,NULL,10);
    const char *sr=getenv("GPACK_H3_SHORT_READ");if(sr)read_limit=(size_t)strtoull(sr,NULL,10);
    const char *sw=getenv("GPACK_H3_SHORT_WRITE");if(sw)write_limit=(size_t)strtoull(sw,NULL,10);
    FILE *manifest=fopen(argv[1],"rb"); if(!manifest){perror("manifest");return 1;}
    char *line=NULL;size_t cap=0;ssize_t len;uint32_t count=0;
    while((len=getline(&line,&cap,manifest))!=-1)if(len>1)count++;
    rewind(manifest);
    size_t tmp_len=strlen(argv[2])+5;char *tmp=malloc(tmp_len);
    if(!tmp){fclose(manifest);free(line);return 1;}
    snprintf(tmp,tmp_len,"%s.tmp",argv[2]);out=fopen(tmp,"wb");
    if(!out){perror("output");fclose(manifest);free(line);free(tmp);return 1;}
    written=0;int ok=write_all("GPKH3\0\0\0",8)&&put_u32(count);
    while(ok&&(len=getline(&line,&cap,manifest))!=-1){
        if(len<=1)continue;
        while(len>0&&(line[len-1]=='\n'||line[len-1]=='\r'))line[--len]=0;
        char *first=strchr(line,'\t');if(!first){ok=0;break;}*first++=0;
        char *second=strchr(first,'\t');if(!second){ok=0;break;}*second++=0;
        char *end=NULL;unsigned long long raw=strtoull(second,&end,10);
        size_t path_len=strlen(first);
        if(!end||*end||path_len>UINT32_MAX||!put_u32((uint32_t)path_len)||!put_u64(raw)||!write_all(first,path_len)||!stream_frame(line))ok=0;
    }
    if(ferror(manifest))ok=0;
    if(fflush(out)||fsync(fileno(out)))ok=0;
    if(fclose(out))ok=0;out=NULL;
    fclose(manifest);free(line);
    if(ok&&rename(tmp,argv[2]))ok=0;
    if(!ok)remove(tmp);
    free(tmp);
    return ok?0:1;
}
