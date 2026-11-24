// Expected checksum of the protected buffer, computed on a PC:   gcc -O2 -o host_ref host_ref.c && ./host_ref
#include <stdint.h>
#include <stdio.h>
#include "common.h"
int main(void) {
    uint32_t s = 0x12345678u;
    for (uint32_t i = 0; i < NWORDS; i++) s = rol5(s) ^ golden(i) ^ (0x01000193u + i);
    printf("0x%08X\n", s);
    return 0;
}
