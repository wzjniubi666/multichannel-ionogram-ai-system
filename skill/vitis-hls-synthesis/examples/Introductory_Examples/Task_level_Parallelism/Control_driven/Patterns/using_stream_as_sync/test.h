

#include <hls_stream.h>

#define N 3

void dut(hls::stream<int> &inputStream, int A[N][N], hls::stream<int> &outputStream);
