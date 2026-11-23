/*
 * Prechess UCI x86-64-v3 (AVX2/BMI/BMI2/FMA/POPCNT) Startup CPU Guard.
 * MUST be compiled with baseline -march=x86-64 -mtune=generic so no VEX/AVX2
 * instructions execute before CPUID/XGETBV verification completes.
 */

#include <stdio.h>
#include <stdlib.h>

__attribute__((constructor, used))
void prechess_check_avx2_cpu(void) {
    __builtin_cpu_init();
    if (!__builtin_cpu_supports("avx2") ||
        !__builtin_cpu_supports("bmi") ||
        !__builtin_cpu_supports("bmi2") ||
        !__builtin_cpu_supports("fma") ||
        !__builtin_cpu_supports("popcnt")) {
        fprintf(
            stderr,
            "info string ERROR: This Prechess UCI binary requires an x86-64-v3 "
            "(AVX2/BMI/BMI2/FMA/POPCNT) CPU with OSXSAVE enabled.\n"
            "info string Run prechess-0.9.9.17.34-win64-universal.exe on this machine.\n"
        );
        fflush(stderr);
        _exit(1);
    }
}
