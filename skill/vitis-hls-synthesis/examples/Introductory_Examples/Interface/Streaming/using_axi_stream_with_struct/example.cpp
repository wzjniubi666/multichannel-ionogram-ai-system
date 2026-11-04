
#include "example.h"

void example(mystream& A, mystream& B) {
#pragma HLS INTERFACE axis port = A
#pragma HLS INTERFACE axis port = B

    data_t tmp_a;

    do {
        tmp_a = A.read();
        data_t tmp_b;
        tmp_b.data.real(tmp_a.data.real() + 5);
        tmp_b.data.imag(tmp_a.data.imag() + 1);
        B.write(tmp_b);
    } while (!tmp_a.last);
}
