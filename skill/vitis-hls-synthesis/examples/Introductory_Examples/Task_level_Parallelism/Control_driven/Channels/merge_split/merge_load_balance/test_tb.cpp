
#include "test.h"

int main() {
    hls::stream<int> a;
    hls::stream<int> b1;
    hls::stream<int> b2;
    hls::stream<int> b3;
    hls::stream<int> b4;
    int cnt1 = 0;
    int cnt2 = 0;
    int cnt3 = 0;
    int cnt4 = 0;

    for (int i = 0; i < 16; i++) {
        b1.write(i);
        b2.write(i);
        b3.write(i);
        b4.write(i);
    }

    dut(a, b1, b2, b3, b4);

    int sum = 0;
    for (int i = 0; i < 64; i++) {
        int tmp1 = a.read();
        sum += tmp1;
    }

    if (sum != 480)
        return 1;

    return 0;
}
