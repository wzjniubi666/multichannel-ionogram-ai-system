
#include "test.h"
#include <cstdio>

int main() {
    int a[N];
    int b[N];

    for (int i = 0; i < N; i++)
        a[i] = i;
    dut(a, b, N);
    for (int i = 0; i < N; i++) {
        if (b[i] != a[i] * 2 + 1) {
            printf("i=%d %d!=%d FAIL\n", i, b[i], a[i] * 2 + 1);
            return 1;
        }
    }
    return 0;
}
