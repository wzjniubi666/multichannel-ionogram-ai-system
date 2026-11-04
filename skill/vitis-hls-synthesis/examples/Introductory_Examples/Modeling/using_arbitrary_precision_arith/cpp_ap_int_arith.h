

#ifndef _CPP_AP_INT_ARITH_H_
#define _CPP_AP_INT_ARITH_H_

#include "ap_int.h"
#include <stdio.h>

#define N 9

// Old data types
// typedef char dinA_t;
// typedef short dinB_t;
// typedef int dinC_t;
// typedef long long dinD_t;
// typedef int dout1_t;
// typedef unsigned int dout2_t;
// typedef int32_t dout3_t;
// typedef int64_t dout4_t;

typedef ap_int<6> dinA_t;
typedef ap_int<12> dinB_t;
typedef ap_int<22> dinC_t;
typedef ap_int<33> dinD_t;

typedef ap_int<18> dout1_t;
typedef ap_uint<13> dout2_t;
typedef ap_int<22> dout3_t;
typedef ap_int<6> dout4_t;

void cpp_ap_int_arith(dinA_t inA, dinB_t inB, dinC_t inC, dinD_t inD,
                      dout1_t* out1, dout2_t* out2, dout3_t* out3,
                      dout4_t* out4);

#endif
