
#include "test.h"

int main() {
    int in[N];
    int out[N];

    for (int i = 0; i < N; i++) {
        in[i] = i;
        out[i] = 0;
    }

    test(in, out, 5);

    return 0;
}
