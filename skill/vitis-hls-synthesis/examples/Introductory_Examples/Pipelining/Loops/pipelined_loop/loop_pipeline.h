

#ifndef _LOOP_PIPELINE_H_
#define _LOOP_PIPELINE_H_

#include <fstream>
#include <iostream>
using namespace std;

#include "ap_int.h"
#define N 20
#define NUM_TRANS 20

typedef ap_int<5> din_t;
typedef ap_int<20> dout_t;

dout_t loop_pipeline(din_t A[N]);

#endif
