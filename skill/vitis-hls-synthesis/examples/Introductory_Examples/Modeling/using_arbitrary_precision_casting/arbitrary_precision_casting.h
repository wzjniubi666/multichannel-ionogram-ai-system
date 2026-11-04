

#ifndef _ARBITRARY_PRECISION_CASTING_H_
#define _ARBITRARY_PRECISION_CASTING_H_

#include <fstream>
#include <iostream>
using namespace std;

#include "ap_int.h"

typedef ap_int<18> din_t;
typedef ap_int<36> dout_t;

dout_t arbitrary_precision_casting(din_t a, din_t b);

#endif
