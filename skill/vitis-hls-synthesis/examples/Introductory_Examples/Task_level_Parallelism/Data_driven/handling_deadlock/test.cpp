
#include "test.h"

void func1(hls::stream<int>& in, hls::stream<int>& out) {
    int offset;
    int c = in.read();
    offset = 0;
    offset = offset << 16;
    out.write(c + offset);
}

void func3(hls::stream<int>& in, hls::stream<int>& out) {
    int c = in.read(); // First read
    c = in.read();     // Second read CAUSES DEADLOCK
    out.write(c);
}

void func2(hls::stream<int>& in, hls::stream<int>& out) {
    int c = in.read();
    out.write(c);
}

void read_in(int* in, int n, hls::stream<int>& s) {
    for (int i = 0; i < n; i++)
        s.write(in[i]);
}

void write_out(int* out, int n, hls::stream<int>& s) {
    for (int i = 0; i < n; i++)
        out[i] = s.read();
}

void test(int* in, int* out, int n) {
#pragma HLS interface m_axi port = in depth = 100
#pragma HLS interface m_axi port = out depth = 100
#pragma HLS dataflow
    hls_thread_local hls::stream<int, 100> s1;
    hls_thread_local hls::stream<int, 100> s2_0, s2_1, s2_2;
    hls_thread_local hls::stream<int, 100> s3;

    hls_thread_local hls::task t2(func2, s2_2, s3);
    hls_thread_local hls::task t1(func1, s1, s2_0);
    hls_thread_local hls::task t3_1(func3, s2_0, s2_1);
    hls_thread_local hls::task t3_2(func3, s2_1, s2_2);

    read_in(in, n, s1);
    write_out(out, n, s3);
}
