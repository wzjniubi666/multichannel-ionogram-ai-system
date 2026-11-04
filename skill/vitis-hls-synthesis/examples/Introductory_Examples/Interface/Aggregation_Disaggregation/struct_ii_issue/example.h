

#include <iostream>
#define NUM 100

// struct alignas(32) A { /* Total size = 256 bits or 32 bytes */
struct A { /* Total size = 192 bits (32 x 6) or 24 bytes */
    int s_1;
    int s_2;
    int s_3;
    int s_4;
    int s_5;
    int s_6;
};

// Top function
void dut(A a_in[NUM], A a_out[NUM], int size);
