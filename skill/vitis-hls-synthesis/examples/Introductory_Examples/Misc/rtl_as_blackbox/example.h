

#ifndef _EXAMPLE_H_
#define _EXAMPLE_H_

#include <fstream>
#include <iostream>
using namespace std;

#include "ap_int.h"

typedef ap_int<10> data_t;

void example(data_t a1, data_t a2, data_t a3, data_t a4, data_t b1, data_t b2,
             data_t b3, data_t b4, data_t& sigma);

#endif
