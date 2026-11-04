

#include "example.h"

void example(hls::stream<packet>& A, hls::stream<packet>& B) {
#pragma HLS INTERFACE axis port = A
#pragma HLS INTERFACE axis port = B

    packet tmp = A.read();
    tmp.data = tmp.data + 5;
    B.write(tmp);
}
