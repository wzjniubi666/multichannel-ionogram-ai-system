

#include "example.h"
#include <iostream>

int main() {
    A arr[N], out[N];
    for (unsigned i = 0; i < N; i++)
        arr[i].c = arr[i].i = i;

    dut(arr, out);
    for (unsigned i = 0; i < N; i++) {
        std::cout << i << ": " << int(out[i].c) << ", " << out[i].i
                  << std::endl;
        if (out[i].c != i || out[i].i != i)
            return 1;
    }
    return 0;
}
