
#ifndef __EXAMPLE_H__
#define __EXAMPLE_H__

#include "hls_vector.h"
#include <ap_int.h>

#define NUM 32

// Each vector will be 64 bytes (16 x 4 bytes)
typedef hls::vector<float, 16> float16;

extern "C" void example(float16* res, const float16* lhs, const float16* rhs,
                        int n);

#endif
