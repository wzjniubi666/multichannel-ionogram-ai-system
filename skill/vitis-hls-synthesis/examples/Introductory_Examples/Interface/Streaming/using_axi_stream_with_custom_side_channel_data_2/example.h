

#pragma once

#include "ap_axi_sdata.h"
#include "hls_stream.h"
#include <iostream>

typedef hls::axis_user<13, (AXIS_ENABLE_USER | AXIS_ENABLE_LAST)> packet;

#define SIZE 5

void example(hls::stream<packet>& A, hls::stream<packet>& B);
