
#include "hls_stream.h"
#include <iostream>

#define N 10

struct A {
    hls::stream<int> s_in;
    long arr[N];
};

// Top function
long dut(struct A& d);
