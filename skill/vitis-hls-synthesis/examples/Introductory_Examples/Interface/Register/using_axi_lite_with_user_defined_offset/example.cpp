

#include <stdio.h>
// In this example the user uses to define the offset and the range is dependent
// on the datatype and port protocol it usese. See the saxi lite  documentation
// which explains the example in more detail

void example(char* a, char* b, char* c) {
#pragma HLS INTERFACE s_axilite port = a bundle = BUS_A offset = 0x20
#pragma HLS INTERFACE s_axilite port = b bundle = BUS_A offset = 0x28
#pragma HLS INTERFACE s_axilite port = c bundle = BUS_A offset = 0x30
#pragma HLS INTERFACE s_axilite port = return bundle = BUS_A

    *c += *a + *b;
}
