
#pragma once

#include "hls_task.h"
#define N 100
#include <iostream>
#include "hls_directio.h"
void test(hls::stream<int>& in, hls::stream<int>& out, hls::ap_hs<int> &n);

