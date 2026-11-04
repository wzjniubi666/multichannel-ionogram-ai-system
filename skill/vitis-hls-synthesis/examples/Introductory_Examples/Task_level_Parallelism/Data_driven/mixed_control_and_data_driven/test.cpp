
#include "test.h"

void worker(hls::stream<int>& in, hls::stream<int>& out) {
    int i = in.read();
    int o = i * 2 + 1;
    out.write(o);
}

void read_in(int* in, int n, hls::stream<int>& out) {
    for (int i = 0; i < n; i++) {
        out.write(in[i]);
    }
}

void write_out(hls::stream<int>& in, int* out, int n) {
    for (int i = 0; i < n; i++) {
        out[i] = in.read();
    }
}

void dut(int in[N], int out[N], int n) {
    hls_thread_local hls::split::round_robin<int, NP> split1;
    hls_thread_local hls::merge::round_robin<int, NP> merge1;
#pragma HLS dataflow

    read_in(in, n, split1.in);

    // Task-Channels
    hls_thread_local hls::task t[NP];
    for (int i = 0; i < NP; i++) {
#pragma HLS unroll
        t[i](worker, split1.out[i], merge1.in[i]);
    }

    write_out(merge1.out, out, n);
}
