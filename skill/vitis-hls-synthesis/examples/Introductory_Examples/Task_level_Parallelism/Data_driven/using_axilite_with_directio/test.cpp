
#include "test.h"

void sub_task1(hls::stream<int>& in, hls::stream<int>& out) {
    int c = in.read();
    out.write(c + 2);
}

void sub_task2(hls::stream<int>& in, hls::stream<int>& out) {
    int c = in.read();
    out.write(c - 2);
}

void task2(hls::stream<int>& in, hls::stream<int>& out, hls::ap_none<int> &n) {
    int c = in.read();
    int var = n.read();
    out.write(c + var);
}

void test(hls::stream<int>& in, hls::stream<int>& out, hls::ap_none<int> &bias) {
#pragma HLS interface s_axilite port=bias
    hls_thread_local hls::stream<int> s1;
    hls_thread_local hls::stream<int> s2;
    hls_thread_local hls::task t(task2, s2, out, bias);
    hls_thread_local hls::task t1(sub_task1, in, s1);
    hls_thread_local hls::task t2(sub_task2, s1, s2);
}
