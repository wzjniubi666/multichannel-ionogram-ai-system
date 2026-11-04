
#include "fft_top.h"

#if USE_STREAM_INTERFACE
// Stream interface implementation
void fft_top(bool direction,
             hls::stream<hls::vector<cmpxDataIn, FFT_SSR>> &in,
             hls::stream<hls::vector<cmpxDataOut, FFT_SSR>> &out,
             bool* status)
{
#pragma HLS interface ap_hs port = direction
#pragma HLS interface ap_fifo depth = 1 port = status
#pragma HLS dataflow

    // no direction and no overflow for SSR>1
    hls::fft<config1>(in, out);
}

#else
// Array interface implementation
void fft_top(bool direction, std::complex<data_in_t> in[FFT_LENGTH],
             std::complex<data_out_t> out[FFT_LENGTH], bool* status) {
#pragma HLS interface ap_hs port = direction
#pragma HLS interface ap_fifo depth = 1 port = status
#pragma HLS dataflow

    // no direction parameter for SSR>1 array interface
    hls::fft<config1>(in, out);
}
#endif

