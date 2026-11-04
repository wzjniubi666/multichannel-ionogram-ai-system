
#include "test.h"

void producer(hls::stream<ap_uint<32>>& out, hls::stream<int>& in) {
#pragma HLS inline off
    ap_uint<32> tmp;
    for (int i = 0; i < 16; i++) {
        int tmp_d = in.read();
        out.write(tmp_d);
    }
}

void consumer1(hls::stream<ap_uint<32>>& in, hls::stream<ap_uint<32>>& out) {
#pragma HLS inline off
    for (int i = 0; i < 4; i++) {
        ap_uint<32> tmp = in.read();
        out.write(tmp);
    }
}

void consumer2(hls::stream<ap_uint<32>>& in, hls::stream<ap_uint<32>>& out) {
#pragma HLS inline off
    for (int i = 0; i < 4; i++) {
        ap_uint<32> tmp = in.read();
        out.write(tmp);
    }
}

void consumer3(hls::stream<ap_uint<32>>& in, hls::stream<ap_uint<32>>& out) {
#pragma HLS inline off
    for (int i = 0; i < 4; i++) {
        ap_uint<32> tmp = in.read();
        out.write(tmp);
    }
}

void consumer4(hls::stream<ap_uint<32>>& in, hls::stream<ap_uint<32>>& out) {
#pragma HLS inline off
    for (int i = 0; i < 4; i++) {
        ap_uint<32> tmp = in.read();
        out.write(tmp);
    }
}

void dut(hls::stream<int>& in1, hls::stream<ap_uint<32>>& out1,
         hls::stream<ap_uint<32>>& out2, hls::stream<ap_uint<32>>& out3,
         hls::stream<ap_uint<32>>& out4) {
#pragma HLS dataflow

    hls::split::round_robin<ap_uint<32>, 4, 2, 100> s;

    producer(s.in, in1);
    consumer1(s.out[0], out1);
    consumer2(s.out[1], out2);
    consumer3(s.out[2], out3);
    consumer4(s.out[3], out4);
}
