#ifndef __MIXED_DATAFLOW_TASK_CHANNEL__
#define __MIXED_DATAFLOW_TASK_CHANNEL__

#include "hls_np_channel.h"
#include "hls_task.h"

const int N = 16;
const int NP = 4;

void dut(int in[N], int out[N], int n);

#endif
