
#ifndef __ARRAY_OF_STREAMS_EXAMPLE__
#define __ARRAY_OF_STREAMS_EXAMPLE__

#include "hls_stream.h"
#include <iostream>

#define M 3

extern int dut(hls::stream<int> s_in[M], hls::stream<int> s_out[M]);

#endif
