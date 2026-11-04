#ifndef __UNIQUE_TASK_REGION__
#define __UNIQUE_TASK_REGION__

#include "hls_task.h"

void top(hls::stream<int>& in1, hls::stream<int>& out1, hls::stream<int>& in2,
         hls::stream<int>& out2, hls::stream<int>& in3, hls::stream<int>& out3,
         hls::stream<int>& in4, hls::stream<int>& out4);

#endif
