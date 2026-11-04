

#ifndef _CPP_AP_FIXED_H_
#define _CPP_AP_FIXED_H_

#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
using namespace std;
#include "ap_fixed.h"

typedef ap_ufixed<10, 8, AP_RND, AP_SAT> din1_t;
typedef ap_fixed<6, 3, AP_RND, AP_WRAP> din2_t;
typedef ap_fixed<22, 17, AP_TRN, AP_SAT> dint_t;
typedef ap_fixed<36, 30> dout_t;

dout_t cpp_ap_fixed(din1_t d_in1, din2_t d_in2);

#endif
