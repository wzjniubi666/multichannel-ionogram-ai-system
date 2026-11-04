

#include "example.h"

int dut(hls::stream<int> s_in[M], hls::stream<int> s_out[M]) {
#pragma HLS INTERFACE axis port = s_in
#pragma HLS INTERFACE axis port = s_out

    int sum = 0;
    for (unsigned j = 0; j < M; j++) {
        for (unsigned i = 0; i < 10; i++) {
            int val = s_in[j].read();
            s_out[j].write(val + 2);
            sum += val;
        }
    }
    return sum;
}
