

#include "example.h"

void example(hls::stream<packet>& A, hls::stream<packet>& B) {
#pragma HLS INTERFACE axis port = A
#pragma HLS INTERFACE axis port = B

    packet tmp = A.read();
    tmp.set_user(tmp.get_user() + 5);
    B.write(tmp);
}
