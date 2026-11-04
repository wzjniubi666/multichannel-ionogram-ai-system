
#include "example.h"

int main() {
    A arr[N];
    for (unsigned i = 0; i < N; i++) {
        arr[i].foo = i;
        arr[i].bar = i;
    }
    auto ret = dut(arr);
    std::cout << "ret = " << ret << std::endl;
    if (ret != 90)
        return 1;
    return 0;
}
