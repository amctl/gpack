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

#define MAX_FILES 1000000u
#define MAX_INDEX (64u * 1024u * 1024u)
#define MAX_ASSET (8ULL * 1024ULL * 1024ULL * 1024ULL)
#define READERS 4

typedef struct { char *path; uint32_t crc; } Expected;
typedef struct { char *path; uint64_t raw, offset, compressed; uint32_t crc; } Record;
static int archive_fd;
static Record *records;
static uint64_t record_count, next_record, bytes_done;
static uint64_t *latencies;
static uint64_t *query_order;
static uint64_t max_working;
static int failed;
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;

static uint32_t u32le(const unsigned char *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
static uint64_t u64le(const unsigned char *p) {
    uint64_t v=0; for(int i=0;i<8;i++)v|=(uint64_t)p[i]<<(8*i); return v;
}
static int read_at(int fd, uint64_t off, void *out, size_t n) {
    size_t done=0;
    while(done<n){ssize_t r=pread(fd,(unsigned char*)out+done,n-done,(off_t)(off+done));
        if(r<0&&errno==EINTR)continue;if(r<=0)return 0;done+=(size_t)r;}
    return 1;
}
static int safe_path(const char *p) {
    if(!*p||p[0]=='/'||strchr(p,'\\'))return 0;
    const char *start=p;
    for(const char *q=p;;q++){
        if(*q=='\0'||*q=='/'){
            size_t n=(size_t)(q-start);
            if(!n||(n==1&&start[0]=='.')||(n==2&&start[0]=='.'&&start[1]=='.'))return 0;
            if(!*q)break;start=q+1;
        }
    }
    return 1;
}
static uint32_t crc32_bytes(const unsigned char *p,size_t n){
    uint32_t c=0xffffffffu;
    for(size_t i=0;i<n;i++){c^=p[i];for(int b=0;b<8;b++)c=(c&1)?(c>>1)^0xedb88320u:c>>1;}
    return ~c;
}
static uint64_t ns_now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint64_t)t.tv_sec*1000000000ULL+t.tv_nsec;}

static Expected *read_expected(const char *path,uint64_t *count){
    FILE *f=fopen(path,"rb");if(!f)return NULL;char *line=NULL;size_t cap=0;ssize_t n;
    uint64_t used=0,alloc=256;Expected *xs=calloc(alloc,sizeof(*xs));if(!xs){fclose(f);return NULL;}
    while((n=getline(&line,&cap,f))!=-1){if(n<=1)continue;while(n>0&&(line[n-1]=='\n'||line[n-1]=='\r'))line[--n]=0;
        char *tab=strchr(line,'\t');if(!tab){free(xs);free(line);fclose(f);return NULL;}*tab++=0;
        char *end=NULL;unsigned long value=strtoul(tab,&end,10);
        if(!end||*end||value>UINT32_MAX||!safe_path(line)){free(xs);free(line);fclose(f);return NULL;}
        if(used==alloc){alloc*=2;Expected *next=realloc(xs,alloc*sizeof(*xs));if(!next){free(xs);free(line);fclose(f);return NULL;}xs=next;}
        xs[used].path=strdup(line);xs[used].crc=(uint32_t)value;if(!xs[used].path){free(xs);free(line);fclose(f);return NULL;}used++;
    }
    free(line);if(ferror(f)){fclose(f);free(xs);return NULL;}fclose(f);*count=used;return xs;
}

static int parse_archive(const char *path,Expected *expected,uint64_t expected_count){
    archive_fd=open(path,O_RDONLY|O_CLOEXEC);if(archive_fd<0)return 0;
    struct stat st;if(fstat(archive_fd,&st)||st.st_size<36)return 0;
    unsigned char head[32];if(!read_at(archive_fd,0,head,sizeof head))return 0;
    if(memcmp(head,"GPKH2\0\0\0",8)||u32le(head+8)!=1||u32le(head+12)!=1)return 0;
    uint64_t count=u64le(head+16),index_off=u64le(head+24),file_size=(uint64_t)st.st_size;
    if(count>MAX_FILES||count!=expected_count||index_off<32||index_off>file_size-4||file_size-index_off>MAX_INDEX)return 0;
    size_t index_size=(size_t)(file_size-index_off);unsigned char *index=malloc(index_size);if(!index)return 0;
    if(!read_at(archive_fd,index_off,index,index_size)||u32le(index)!=(uint32_t)count){free(index);return 0;}
    records=calloc(count?count:1,sizeof(*records));if(!records){free(index);return 0;}
    size_t at=4;char *previous=NULL;
    for(uint64_t i=0;i<count;i++){
        if(at>index_size||index_size-at<16){free(index);return 0;}
        uint32_t path_len=u32le(index+at);at+=4;uint64_t raw=u64le(index+at);at+=8;uint32_t segs=u32le(index+at);at+=4;
        if(!path_len||path_len>1024*1024||raw>MAX_ASSET||segs!=1||at>index_size||index_size-at<path_len){free(index);return 0;}
        char *name=malloc((size_t)path_len+1);if(!name){free(index);return 0;}memcpy(name,index+at,path_len);name[path_len]=0;at+=path_len;
        if(!safe_path(name)||(previous&&strcmp(previous,name)>=0)||strcmp(name,expected[i].path)){free(name);free(index);return 0;}
        if(at>index_size||index_size-at<24){free(name);free(index);return 0;}
        uint64_t off=u64le(index+at);at+=8;uint64_t compressed=u64le(index+at);at+=8;uint64_t unpacked=u64le(index+at);at+=8;
        if(off<32||off>index_off||!compressed||compressed>index_off-off||unpacked!=raw){free(name);free(index);return 0;}
        records[i]=(Record){name,raw,off,compressed,expected[i].crc};previous=name;
    }
    if(at!=index_size){free(index);return 0;}free(index);record_count=count;
    return 1;
}

static uint64_t find_record(const char *path){
    uint64_t lo=0,hi=record_count;
    while(lo<hi){uint64_t mid=lo+(hi-lo)/2;int c=strcmp(path,records[mid].path);if(c==0)return mid;if(c<0)hi=mid;else lo=mid+1;}
    return UINT64_MAX;
}

static void *reader(void *unused){(void)unused;
    for(;;){pthread_mutex_lock(&mutex);uint64_t task=next_record++;pthread_mutex_unlock(&mutex);if(task>=record_count)break;
        uint64_t i=query_order[task];
        Record *r=&records[i];if(r->compressed>SIZE_MAX||r->raw>SIZE_MAX){pthread_mutex_lock(&mutex);failed=1;pthread_mutex_unlock(&mutex);continue;}
        unsigned char *enc=malloc((size_t)(r->compressed?r->compressed:1));unsigned char *raw=malloc((size_t)(r->raw?r->raw:1));
        if(!enc||!raw){free(enc);free(raw);pthread_mutex_lock(&mutex);failed=1;pthread_mutex_unlock(&mutex);continue;}
        uint64_t start=ns_now();int ok=read_at(archive_fd,r->offset,enc,(size_t)r->compressed);
        size_t frame=ok?ZSTD_findFrameCompressedSize(enc,(size_t)r->compressed):0;
        size_t got=(!ZSTD_isError(frame)&&frame==r->compressed)?ZSTD_decompress(raw,(size_t)r->raw,enc,(size_t)r->compressed):ZSTD_CONTENTSIZE_ERROR;
        uint32_t crc=(!ZSTD_isError(got)&&got==r->raw)?crc32_bytes(raw,got):0;
        uint64_t elapsed=ns_now()-start;
        if(ZSTD_isError(got)||got!=r->raw||crc!=r->crc)ok=0;
        pthread_mutex_lock(&mutex);latencies[task]=elapsed;bytes_done+=r->raw;
        uint64_t working=r->raw+r->compressed;if(working>max_working)max_working=working;if(!ok)failed=1;pthread_mutex_unlock(&mutex);
        free(enc);free(raw);
    }
    return NULL;
}
static int cmp_u64(const void *a,const void *b){uint64_t x=*(const uint64_t*)a,y=*(const uint64_t*)b;return x<y?-1:x>y?1:0;}

int main(int argc,char **argv){
    if(argc<3){fprintf(stderr,"usage: c_reference ARCHIVE EXPECTED_CRC_TSV [validate]\n");return 2;}
    uint64_t parse_started=ns_now(),expected_count=0;Expected *expected=read_expected(argv[2],&expected_count);if(!expected){fprintf(stderr,"bad expected manifest\n");return 1;}
    if(!parse_archive(argv[1],expected,expected_count)){fprintf(stderr,"invalid archive/index\n");return 1;}
    uint64_t parse_ns=ns_now()-parse_started;
    if(argc>3){puts("VALID");return 0;}
    latencies=calloc(record_count?record_count:1,sizeof(*latencies));if(!latencies)return 1;
    query_order=calloc(record_count?record_count:1,sizeof(*query_order));if(!query_order)return 1;
    uint64_t started=ns_now();
    for(uint64_t i=0;i<expected_count;i++){query_order[i]=find_record(expected[i].path);if(query_order[i]==UINT64_MAX){fprintf(stderr,"runtime path lookup failed\n");return 1;}}
    pthread_t tids[READERS];int created=0;
    for(int i=0;i<READERS;i++){if(pthread_create(&tids[i],NULL,reader,NULL)){failed=1;break;}created++;}
    for(int i=0;i<created;i++)pthread_join(tids[i],NULL);
    if(created!=READERS)failed=1;
    uint64_t elapsed=ns_now()-started;qsort(latencies,record_count,sizeof(*latencies),cmp_u64);
    double mib=(double)bytes_done/1048576.0/((double)elapsed/1e9);
    uint64_t p50=record_count?latencies[(record_count-1)/2]:0,p95=record_count?latencies[(record_count-1)*95/100]:0;
    printf("H3RUNTIME c-reference %llu %llu %.9f %.9f %.3f %.6f %.6f %llu\n",
           (unsigned long long)record_count,(unsigned long long)bytes_done,(double)parse_ns/1e9,
           (double)elapsed/1e9,mib,(double)p50/1e6,(double)p95/1e6,(unsigned long long)max_working);
    return failed?1:0;
}
