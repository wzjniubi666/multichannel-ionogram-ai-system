#ifndef __MERGE_ROUND_ROBIN_HH__
#define __MERGE_ROUND_ROBIN_HH__

#include "hls_np_channel.h"
#include "hls_stream.h"

void dut(hls::stream<int>& in1, hls::stream<int>& out1, hls::stream<int>& out2,
         hls::stream<int>& out3, hls::stream<int>& out4);

#endif
