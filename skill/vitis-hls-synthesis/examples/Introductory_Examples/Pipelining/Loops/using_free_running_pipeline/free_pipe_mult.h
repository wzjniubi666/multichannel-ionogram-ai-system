

#include "ap_axi_sdata.h"
#include "hls_stream.h"
#include "math.h"
using namespace hls;

typedef double data_t;
#define SZ 8

void free_pipe_mult(data_t A[SZ], hls::stream<data_t>& strm, data_t& out);
