

typedef unsigned int data_t;
#include <hls_stream.h>
#include <hls_vector.h>
#include <iostream>
#include <vector>

#define NUM_WORDS 16

// Each vector will be 64 bytes (16 x 4 bytes)
typedef hls::vector<uint32_t, NUM_WORDS> vecOf16Words;

extern "C" {
// Top function
void diamond(vecOf16Words* vecIn, vecOf16Words* vecOut, int size);
}

// Sub functions

void load(vecOf16Words* in, hls::stream<vecOf16Words>& out, int vSize);
void compute_A(hls::stream<vecOf16Words>& in, hls::stream<vecOf16Words>& out1,
               hls::stream<vecOf16Words>& out2, int vSize);
void compute_B(hls::stream<vecOf16Words>& in, hls::stream<vecOf16Words>& out,
               int vSize);
void compute_C(hls::stream<vecOf16Words>& in, hls::stream<vecOf16Words>& out,
               int vSize);
void compute_D(hls::stream<vecOf16Words>& in1, hls::stream<vecOf16Words>& in2,
               hls::stream<vecOf16Words>& out, int vSize);
void store(hls::stream<vecOf16Words>& in, vecOf16Words* out, int vSize);
