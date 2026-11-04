

#ifndef _ARRAY_MEM_PERFORM_H_
#define _ARRAY_MEM_PERFORM_H_

#include <fstream>
#include <iostream>
using namespace std;

#include "ap_int.h"
#define N 128

typedef ap_int<8> din_t;
typedef ap_int<16> dout_t;

dout_t mem_bottleneck_resolved(din_t mem[N]);

#endif
