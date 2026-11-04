

#ifndef _POINTER_STREAM_GOOD_H_
#define _POINTER_STREAM_GOOD_H_

#include <stdio.h>

typedef int din_t;
typedef int dout_t;

void pointer_stream_good(volatile dout_t* d_o, volatile din_t* d_i);

#endif
