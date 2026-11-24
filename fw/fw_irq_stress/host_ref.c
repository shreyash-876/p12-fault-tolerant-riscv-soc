// Computes the expected checksum of the stress workload on a PC:   gcc -O2 -o host_ref host_ref.c && ./host_ref
#include <stdint.h>
#include <stdio.h>
static uint32_t ms;
#define WL_CSR_WRITE(v) (ms = (v))
#define WL_CSR_READ()   (ms)
#include "workload.h"
int main(void) {
    for (int i = 0; i < 64; i++) { arr[i] = 0; bytes[i] = 0; }
    printf("0x%08X\n", run_all());
    return 0;
}
