

#ifndef _ARRAY_MEM_BOTTLENECK_H_
#define _ARRAY_MEM_BOTTLENECK_H_

#include <fstream>
#include <iostream>
using namespace std;

#include "ap_int.h"
#define N 128

typedef ap_int<7> din_t;
typedef ap_int<10> dout_t;

dout_t array_mem_bottleneck(din_t mem[N]);

#endif
