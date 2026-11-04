

#include "free_pipe_mult.h"
#include <iostream>

int accumulate(data_t A[]) {
#pragma HLS inline off

    data_t acc = 0.0;
    for (int i = 0; i < SZ; i++) {
        std::cout << "A: " << A[i] << std::endl;
        acc += A[i];
    }
    return acc;
}

void process(hls::stream<data_t>& strm_in, hls::stream<data_t>& strm_out) {
#pragma HLS inline off

    for (int i = 0; i < SZ; i++) {
        data_t tmp;
        tmp = strm_in.read();
        strm_out.write(tmp);
    }
}

void inner(data_t A[SZ], hls::stream<data_t>& stream_in, data_t* out) {
#pragma HLS pipeline

#pragma HLS INTERFACE ap_fifo port = stream_in
    data_t regA[SZ];
#pragma HLS ARRAY_PARTITION variable = regA complete
    for (int i = 0; i < SZ; i++) {
        data_t tmp;
        tmp = stream_in.read();
        regA[i] = A[i] + tmp;
    }

    *out = accumulate(regA);
}

void free_pipe_mult(data_t A[SZ], hls::stream<data_t>& strm, data_t& out) {
#pragma HLS DATAFLOW
#pragma HLS INTERFACE ap_fifo port = strm

    data_t B[SZ];

    for (int i = 0; i < SZ; i++)
        B[i] = A[i] + i;

    hls::stream<data_t> strm_out;
    process(strm, strm_out);
    inner(B, strm_out, &out);
}
