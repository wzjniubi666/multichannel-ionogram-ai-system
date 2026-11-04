
#include "example.h"

int main() {
    A a_in[NUM];
    A a_out[NUM];

    for (unsigned i = 0; i < NUM; i++) {
        a_in[i].s_1 = i;
        a_in[i].s_2 = i + 1;
        a_in[i].s_3 = i + 2;
        a_in[i].s_4 = i + 3;
        a_in[i].s_5 = i + 4;
        a_in[i].s_6 = i + 5;
    }

    int size = 8;

    dut(a_in, a_out, size);

    for (unsigned int i = 0; i < NUM; i++) {
        if (a_out[i].s_1 != a_in[i].s_1 + size) {
            return -1;
        }
    }
    printf("Test Pass!\n");
    return 0;
}
