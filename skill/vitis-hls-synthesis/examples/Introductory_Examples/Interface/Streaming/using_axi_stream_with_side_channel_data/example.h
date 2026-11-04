

#pragma once

#include "ap_axi_sdata.h"
#include "hls_stream.h"
#include <iostream>

typedef ap_axis<32, 2, 5, 6> packet;

#define SIZE 5

void example(hls::stream<packet>& A, hls::stream<packet>& B);
