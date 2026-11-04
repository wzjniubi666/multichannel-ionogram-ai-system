

#include "example.h"

int main() {
    A a;
    for (unsigned i = 0; i < N; i++)
        a.s_in.write(i);
    for (unsigned i = 0; i < N; i++)
        a.arr[i] = i;

    auto ret = dut(a);
    std::cout << "ret = " << ret << std::endl;

    return 0;
}
