#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <zstd.h>

#define READERS 4
#define MAX_ENTRIES 1000000u
#define MAX_INDEX (64u * 1024u * 1024u)
#define MAX_ASSET (8ULL * 1024ULL * 1024ULL * 1024ULL)
typedef struct { char *path; uint32_t crc; } Expected;
typedef struct { char *path; uint8_t codec; uint64_t raw, offset, stored; uint32_t crc; } Entry;
typedef struct { uint64_t index; uint32_t crc; } Query;
static int fd;
static Entry *entries;
static Query *queries;
static uint64_t count, next_query, total_bytes;
static uint64_t *latencies;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int failed;

static uint16_t u16(const unsigned char *p) { return (uint16_t)p[0] | (uint16_t)p[1] << 8; }
static uint32_t u32(const unsigned char *p) { return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24; }
static uint64_t u64(const unsigned char *p) { uint64_t n=0; for(int i=0;i<8;i++) n|=(uint64_t)p[i]<<(i*8); return n; }
static uint64_t ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (uint64_t)t.tv_sec*1000000000ULL+t.tv_nsec; }
static uint32_t crc32(const unsigned char *p,size_t n) {
    static const uint32_t table[256]={
+        0x00000000u, 0x77073096u, 0xee0e612cu, 0x990951bau,
        0x076dc419u, 0x706af48fu, 0xe963a535u, 0x9e6495a3u,
        0x0edb8832u, 0x79dcb8a4u, 0xe0d5e91eu, 0x97d2d988u,
        0x09b64c2bu, 0x7eb17cbdu, 0xe7b82d07u, 0x90bf1d91u,
        0x1db71064u, 0x6ab020f2u, 0xf3b97148u, 0x84be41deu,
        0x1adad47du, 0x6ddde4ebu, 0xf4d4b551u, 0x83d385c7u,
        0x136c9856u, 0x646ba8c0u, 0xfd62f97au, 0x8a65c9ecu,
        0x14015c4fu, 0x63066cd9u, 0xfa0f3d63u, 0x8d080df5u,
        0x3b6e20c8u, 0x4c69105eu, 0xd56041e4u, 0xa2677172u,
        0x3c03e4d1u, 0x4b04d447u, 0xd20d85fdu, 0xa50ab56bu,
        0x35b5a8fau, 0x42b2986cu, 0xdbbbc9d6u, 0xacbcf940u,
        0x32d86ce3u, 0x45df5c75u, 0xdcd60dcfu, 0xabd13d59u,
        0x26d930acu, 0x51de003au, 0xc8d75180u, 0xbfd06116u,
        0x21b4f4b5u, 0x56b3c423u, 0xcfba9599u, 0xb8bda50fu,
        0x2802b89eu, 0x5f058808u, 0xc60cd9b2u, 0xb10be924u,
        0x2f6f7c87u, 0x58684c11u, 0xc1611dabu, 0xb6662d3du,
        0x76dc4190u, 0x01db7106u, 0x98d220bcu, 0xefd5102au,
        0x71b18589u, 0x06b6b51fu, 0x9fbfe4a5u, 0xe8b8d433u,
        0x7807c9a2u, 0x0f00f934u, 0x9609a88eu, 0xe10e9818u,
        0x7f6a0dbbu, 0x086d3d2du, 0x91646c97u, 0xe6635c01u,
        0x6b6b51f4u, 0x1c6c6162u, 0x856530d8u, 0xf262004eu,
        0x6c0695edu, 0x1b01a57bu, 0x8208f4c1u, 0xf50fc457u,
        0x65b0d9c6u, 0x12b7e950u, 0x8bbeb8eau, 0xfcb9887cu,
        0x62dd1ddfu, 0x15da2d49u, 0x8cd37cf3u, 0xfbd44c65u,
        0x4db26158u, 0x3ab551ceu, 0xa3bc0074u, 0xd4bb30e2u,
        0x4adfa541u, 0x3dd895d7u, 0xa4d1c46du, 0xd3d6f4fbu,
        0x4369e96au, 0x346ed9fcu, 0xad678846u, 0xda60b8d0u,
        0x44042d73u, 0x33031de5u, 0xaa0a4c5fu, 0xdd0d7cc9u,
        0x5005713cu, 0x270241aau, 0xbe0b1010u, 0xc90c2086u,
        0x5768b525u, 0x206f85b3u, 0xb966d409u, 0xce61e49fu,
        0x5edef90eu, 0x29d9c998u, 0xb0d09822u, 0xc7d7a8b4u,
        0x59b33d17u, 0x2eb40d81u, 0xb7bd5c3bu, 0xc0ba6cadu,
        0xedb88320u, 0x9abfb3b6u, 0x03b6e20cu, 0x74b1d29au,
        0xead54739u, 0x9dd277afu, 0x04db2615u, 0x73dc1683u,
        0xe3630b12u, 0x94643b84u, 0x0d6d6a3eu, 0x7a6a5aa8u,
        0xe40ecf0bu, 0x9309ff9du, 0x0a00ae27u, 0x7d079eb1u,
        0xf00f9344u, 0x8708a3d2u, 0x1e01f268u, 0x6906c2feu,
        0xf762575du, 0x806567cbu, 0x196c3671u, 0x6e6b06e7u,
        0xfed41b76u, 0x89d32be0u, 0x10da7a5au, 0x67dd4accu,
        0xf9b9df6fu, 0x8ebeeff9u, 0x17b7be43u, 0x60b08ed5u,
        0xd6d6a3e8u, 0xa1d1937eu, 0x38d8c2c4u, 0x4fdff252u,
        0xd1bb67f1u, 0xa6bc5767u, 0x3fb506ddu, 0x48b2364bu,
        0xd80d2bdau, 0xaf0a1b4cu, 0x36034af6u, 0x41047a60u,
        0xdf60efc3u, 0xa867df55u, 0x316e8eefu, 0x4669be79u,
        0xcb61b38cu, 0xbc66831au, 0x256fd2a0u, 0x5268e236u,
        0xcc0c7795u, 0xbb0b4703u, 0x220216b9u, 0x5505262fu,
        0xc5ba3bbeu, 0xb2bd0b28u, 0x2bb45a92u, 0x5cb36a04u,
        0xc2d7ffa7u, 0xb5d0cf31u, 0x2cd99e8bu, 0x5bdeae1du,
        0x9b64c2b0u, 0xec63f226u, 0x756aa39cu, 0x026d930au,
        0x9c0906a9u, 0xeb0e363fu, 0x72076785u, 0x05005713u,
        0x95bf4a82u, 0xe2b87a14u, 0x7bb12baeu, 0x0cb61b38u,
        0x92d28e9bu, 0xe5d5be0du, 0x7cdcefb7u, 0x0bdbdf21u,
        0x86d3d2d4u, 0xf1d4e242u, 0x68ddb3f8u, 0x1fda836eu,
        0x81be16cdu, 0xf6b9265bu, 0x6fb077e1u, 0x18b74777u,
        0x88085ae6u, 0xff0f6a70u, 0x66063bcau, 0x11010b5cu,
        0x8f659effu, 0xf862ae69u, 0x616bffd3u, 0x166ccf45u,
        0xa00ae278u, 0xd70dd2eeu, 0x4e048354u, 0x3903b3c2u,
        0xa7672661u, 0xd06016f7u, 0x4969474du, 0x3e6e77dbu,
        0xaed16a4au, 0xd9d65adcu, 0x40df0b66u, 0x37d83bf0u,
        0xa9bcae53u, 0xdebb9ec5u, 0x47b2cf7fu, 0x30b5ffe9u,
        0xbdbdf21cu, 0xcabac28au, 0x53b39330u, 0x24b4a3a6u,
        0xbad03605u, 0xcdd70693u, 0x54de5729u, 0x23d967bfu,
        0xb3667a2eu, 0xc4614ab8u, 0x5d681b02u, 0x2a6f2b94u,
        0xb40bbe37u, 0xc30c8ea1u, 0x5a05df1bu, 0x2d02ef8du
    };
    uint32_t c=0xffffffffu;
    for(size_t i=0;i<n;i++){
        c=table[(c^p[i])&255]^(c>>8);
    }
    return ~c;
}
static int pread_all(uint64_t off,void *out,size_t n) {
    size_t done=0;
    while(done<n){
        ssize_t r=pread(fd,(char*)out+done,n-done,(off_t)(off+done));
        if(r<0&&errno==EINTR)continue;
        if(r<=0)return 0;
        done+=(size_t)r;
    }
    return 1;
}
static int safe_path(const unsigned char *p,size_t n) {
    if(!n||n>4096||p[0]=='/'||memchr(p,0,n)||memchr(p,'\\',n))return 0;
    for(size_t i=0;i<n;){
        unsigned char a=p[i];size_t width;
        if(a<0x80){i++;continue;}
        if(a>=0xc2&&a<=0xdf)width=2;
        else if(a>=0xe0&&a<=0xef)width=3;
        else if(a>=0xf0&&a<=0xf4)width=4;
        else return 0;
        if(i+width>n)return 0;
        for(size_t j=1;j<width;j++)if(p[i+j]<0x80||p[i+j]>0xbf)return 0;
        if(width==3&&((a==0xe0&&p[i+1]<0xa0)||(a==0xed&&p[i+1]>=0xa0)))return 0;
        if(width==4&&((a==0xf0&&p[i+1]<0x90)||(a==0xf4&&p[i+1]>=0x90)))return 0;
        i+=width;
    }
    size_t start=0; for(size_t i=0;i<=n;i++) if(i==n||p[i]=='/'){
        size_t z=i-start; if(!z||(z==1&&p[start]=='.')||(z==2&&p[start]=='.'&&p[start+1]=='.'))return 0; start=i+1; }
    return 1;
}
static int find_path(const char *path) {
    uint64_t lo=0,hi=count; while(lo<hi){uint64_t m=lo+(hi-lo)/2;int c=strcmp(entries[m].path,path);if(!c)return (int)m;if(c<0)lo=m+1;else hi=m;}return -1;
}
static int parse_archive(const char *path) {
    fd=open(path,O_RDONLY|O_CLOEXEC); if(fd<0)return 0; struct stat st;
    if(fstat(fd,&st)||st.st_size<68)return 0;
    unsigned char h[64];
    if(!pread_all(0,h,sizeof h)||memcmp(h,"GPKARCH\0",8)||u16(h+8)!=1||u16(h+10)!=0||u32(h+12)!=64)return 0;
    unsigned char hc[64];memcpy(hc,h,64);memset(hc+44,0,4);if(crc32(hc,64)!=u32(h+44))return 0;
    for(int i=48;i<64;i++)if(h[i])return 0;
    count=u64(h+16);uint64_t off=u64(h+24),sz=u64(h+32),fs=(uint64_t)st.st_size;
    if(count>MAX_ENTRIES||sz<4||sz>MAX_INDEX||off<64||off>fs||sz!=fs-off)return 0;
    unsigned char *ix=malloc((size_t)sz);if(!ix||!pread_all(off,ix,(size_t)sz)||crc32(ix,(size_t)sz)!=u32(h+40)){free(ix);return 0;}
    if(u32(ix)!=(uint32_t)count){free(ix);return 0;} entries=calloc(count?count:1,sizeof(*entries));if(!entries){free(ix);return 0;}
    size_t at=4;uint64_t prev_end=64;char *prev=NULL;
    for(uint64_t i=0;i<count;i++){
        if(at>sz||sz-at<40){free(ix);return 0;}uint32_t pn=u32(ix+at);uint8_t codec=ix[at+4];
        if(!pn||pn>4096||ix[at+5]||ix[at+6]||ix[at+7]||u32(ix+at+36)){free(ix);return 0;}
        uint64_t raw=u64(ix+at+8),po=u64(ix+at+16),stored=u64(ix+at+24);uint32_t crc=u32(ix+at+32);at+=40;
        if(pn>sz-at||raw>MAX_ASSET||!safe_path(ix+at,pn)){free(ix);return 0;}
        if(prev){size_t z=strlen(prev);size_t n=z<pn?z:pn;int c=memcmp(prev,ix+at,n);if(c>0||(c==0&&z>=pn)){free(ix);return 0;}}
        entries[i].path=malloc((size_t)pn+1);if(!entries[i].path){free(ix);return 0;}memcpy(entries[i].path,ix+at,pn);entries[i].path[pn]=0;prev=entries[i].path;at+=pn;
        if(codec>1||(codec==0&&stored!=raw)){free(ix);return 0;}
        if(raw==0){if(codec||stored||crc||po<64||po>off){free(ix);return 0;}}
        else {if(!stored||po<prev_end||po>off||stored>off-po){free(ix);return 0;}prev_end=po+stored;}
        entries[i].codec=codec;entries[i].raw=raw;entries[i].offset=po;entries[i].stored=stored;entries[i].crc=crc;
    }
    free(ix);return at==sz;
}
static void *worker(void *unused) {
    (void)unused; for(;;){pthread_mutex_lock(&lock);if(next_query>=count){pthread_mutex_unlock(&lock);return NULL;}uint64_t q=next_query++;pthread_mutex_unlock(&lock);
        Entry *e=&entries[queries[q].index];uint64_t started=ns();unsigned char *src=malloc(e->stored?(size_t)e->stored:1),*dst=malloc(e->raw?(size_t)e->raw:1);
        int ok=src&&dst&&(!e->stored||pread_all(e->offset,src,(size_t)e->stored));
        if(ok&&e->codec==0){if(e->raw)memcpy(dst,src,(size_t)e->raw);}
        else if(ok){size_t frame=ZSTD_findFrameCompressedSize(src,(size_t)e->stored);size_t got=ZSTD_decompress(dst,(size_t)e->raw,src,(size_t)e->stored);ok=!ZSTD_isError(frame)&&frame==e->stored&&!ZSTD_isError(got)&&got==e->raw;}
        if(ok)ok=crc32(dst,(size_t)e->raw)==e->crc&&e->crc==queries[q].crc;
        latencies[q]=ns()-started;pthread_mutex_lock(&lock);if(!ok)failed=1;total_bytes+=e->raw;pthread_mutex_unlock(&lock);free(src);free(dst);
    }
}
static Expected *load_expected(const char *file,uint64_t *n) {
    FILE *f=fopen(file,"rb");if(!f)return NULL;Expected *xs=NULL;uint64_t used=0,cap=0;char *line=NULL;size_t z=0;ssize_t got;
    while((got=getline(&line,&z,f))>0){while(got>0&&(line[got-1]=='\n'||line[got-1]=='\r'))line[--got]=0;if(!got)continue;char *tab=strchr(line,'\t');if(!tab)goto bad;*tab++=0;char *end=NULL;unsigned long v=strtoul(tab,&end,10);if(!end||*end||v>UINT32_MAX||!safe_path((unsigned char*)line,strlen(line)))goto bad;
        if(used==cap){cap=cap?cap*2:128;Expected *p=realloc(xs,cap*sizeof(*xs));if(!p)goto bad;xs=p;}xs[used].path=strdup(line);xs[used].crc=(uint32_t)v;if(!xs[used].path)goto bad;used++;}
    free(line);fclose(f);*n=used;return xs;
bad: free(line);fclose(f);return NULL;
}
static int cmp_u64(const void *a,const void *b){uint64_t x=*(const uint64_t*)a,y=*(const uint64_t*)b;return x<y?-1:x>y?1:0;}
int main(int argc,char **argv) {
    if(argc==2&&!strcmp(argv[1],"--version")){printf("%u\n",ZSTD_versionNumber());return 0;}
    if(argc<3){fprintf(stderr,"usage: c_reference ARCHIVE SOURCE_CRC_TSV [validate]\n");return 2;}
    uint64_t expected_count=0;Expected *xs=load_expected(argv[2],&expected_count);if(!xs){fprintf(stderr,"bad source manifest\n");return 1;}
    uint64_t started=ns();if(!parse_archive(argv[1])){fprintf(stderr,"invalid v1 archive\n");return 1;}uint64_t parse_ns=ns()-started;
    if(expected_count!=count){fprintf(stderr,"manifest count mismatch\n");return 1;}
    queries=calloc(count?count:1,sizeof(*queries));latencies=calloc(count?count:1,sizeof(*latencies));if(!queries||!latencies)return 1;
    for(uint64_t i=0;i<count;i++){int x=find_path(xs[i].path);if(x<0){fprintf(stderr,"source path missing\n");return 1;}queries[i]=(Query){(uint64_t)x,xs[i].crc};}
    if(argc>3){puts("VALID");return 0;}
    pthread_t t[READERS];started=ns();for(int i=0;i<READERS;i++)if(pthread_create(&t[i],NULL,worker,NULL))return 1;for(int i=0;i<READERS;i++)pthread_join(t[i],NULL);uint64_t run_ns=ns()-started;
    if(failed)return 1;
    qsort(latencies,count,sizeof(*latencies),cmp_u64);
    uint64_t p50=latencies[(count-1)/2],p95=latencies[(count-1)*95/100];
    printf("GPKV1 c-reference %llu %llu %llu %llu %.3f %.6f %.6f\n",(unsigned long long)count,(unsigned long long)total_bytes,(unsigned long long)parse_ns,(unsigned long long)run_ns,(double)total_bytes*1e9/(double)run_ns/1048576.0,(double)p50/1e6,(double)p95/1e6);return 0;
}
