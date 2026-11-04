

#ifndef _LOOP_VAR_H_
#define _LOOP_VAR_H_

#include <fstream>
#include <iostream>
using namespace std;

#include "ap_int.h"
#define N 32

typedef ap_int<8> din_t;
typedef ap_int<13> dout_t;
typedef ap_uint<5> dsel_t;

dout_t loop_var(din_t A[N], dsel_t width);

#endif
