

#include "ap_int.h"
#include <iostream>

#define N 10

struct A {
    int foo[3];
    ap_int<23> bar;
};

// Top function
int dut(A arr[N]);
