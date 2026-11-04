#ifndef __SPLIT_ROUND_ROBIN_HH__
#define __SPLIT_ROUND_ROBIN_HH__

#include "ap_int.h"
#include "hls_np_channel.h"
#include "hls_stream.h"

void dut(hls::stream<int>& in1, hls::stream<ap_uint<32>>& out1,
         hls::stream<ap_uint<32>>& out2, hls::stream<ap_uint<32>>& out3,
         hls::stream<ap_uint<32>>& out4);

#endif
