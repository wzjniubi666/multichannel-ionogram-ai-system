
#include "test.h"

int main() {
    hls::stream<int> in1, in2, in3, in4;
    hls::stream<int> out1, out2, out3, out4;
    for (int i = 0; i < 64; i++) {
        in1.write(i);
        in2.write(i);
        in3.write(i);
        in4.write(i);
    }

    for (int j = 0; j < 4; j++) {
        top(in1, out1, in2, out2, in3, out3, in4, out4);
    }

    for (int i = 0; i < 64; i++) {
        int t = out1.read();
        if (t != 2 * i) {
            printf("Error 1 at %d %d != %d\n", i, t, 2 * i);
            return 1;
        }
        t = out2.read();
        if (t != 2 * i) {
            printf("Error 2 at %d %d != %d\n", i, t, 2 * i);
            return 1;
        }
        t = out3.read();
        if (t != 2 * i) {
            printf("Error 3 at %d %d != %d\n", i, t, 2 * i);
            return 1;
        }
        t = out4.read();
        if (t != 2 * i) {
            printf("Error 4 at %d %d != %d\n", i, t, 2 * i);
            return 1;
        }
    }
    printf("PASS\n");
}
