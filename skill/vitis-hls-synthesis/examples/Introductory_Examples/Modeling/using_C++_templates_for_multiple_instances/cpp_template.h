

#ifndef _CPP_TEMPLATE_H_
#define _CPP_TEMPLATE_H_

#include <cstdio>

void cpp_template(int inp, int* out);

template <int K> void func_with_static(int inp, int* dout) {
    // Use inline off pragma to avoid automatic inlining
#pragma HLS INLINE off
    static int acc = 0;
    acc += inp;
    *dout = acc;
}

#endif
