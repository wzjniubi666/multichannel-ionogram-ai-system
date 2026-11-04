
#pragma once
#include "hls_stream.h"
#include "hls_streamofblocks.h"

#define N 100
#define NUM_BLOCKS 10
typedef unsigned char data_t;
typedef data_t block_data_t[NUM_BLOCKS];

// Top function
void diamond(hls::stream<data_t>& vecIn, hls::stream<data_t>& vecOut);

// Sub functions
void funcA(hls::stream<data_t>& in, hls::stream_of_blocks<block_data_t>& out1,
           hls::stream_of_blocks<block_data_t>& out2);
void funcB(hls::stream_of_blocks<block_data_t>& in,
           hls::stream_of_blocks<block_data_t>& out);
void funcC(hls::stream_of_blocks<block_data_t>& in,
           hls::stream_of_blocks<block_data_t>& out);
void funcD(hls::stream_of_blocks<block_data_t>& in1,
           hls::stream_of_blocks<block_data_t>& in2, hls::stream<data_t>& out);
