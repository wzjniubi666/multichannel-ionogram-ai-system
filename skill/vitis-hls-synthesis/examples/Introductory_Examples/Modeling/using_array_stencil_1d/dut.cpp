
#include<string.h>
#define HS 100
#define WS 100
#define FW 3
#define FH 1

void top(float in[HS][WS], float out[HS][WS-FW+1], float var_in) {
#pragma HLS INTERFACE m_axi port=in offset=slave bundle=gmem
#pragma HLS INTERFACE m_axi port=out offset=slave bundle=gmem

#pragma HLS INTERFACE s_axilite port=in bundle=control
#pragma HLS INTERFACE s_axilite port=out bundle=control
#pragma HLS INTERFACE s_axilite port=var_in bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

   for (int i = 0; i < 100; i++) {
     for (int j = 0; j < 100-FW+1; j++) {
#pragma HLS pipeline II=1
#pragma HLS array_stencil variable=in
        out[i][j] = in[i][j] + in[i][j+1] + in[i][j+2] + var_in;
     }
   }
}


