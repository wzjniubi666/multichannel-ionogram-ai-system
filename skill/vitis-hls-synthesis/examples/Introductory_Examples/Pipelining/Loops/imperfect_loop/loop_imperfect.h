

#ifndef _LOOP_IMPERFECT_H_
#define _LOOP_IMPERFECT_H_

#include <fstream>
#include <iostream>
using namespace std;

#include "ap_int.h"
#define N 20

typedef ap_int<5> din_t;
typedef ap_int<12> dint_t;
typedef ap_int<6> dout_t;

void loop_imperfect(din_t A[N], dout_t B[N]);

#endif
