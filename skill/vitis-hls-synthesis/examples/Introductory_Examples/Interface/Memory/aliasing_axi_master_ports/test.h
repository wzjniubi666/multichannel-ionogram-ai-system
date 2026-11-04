

#include <hls_stream.h>
#include <hls_math.h>

const unsigned SIZE = 1024;

template <typename T>
struct dat_t {
	T data;
};

typedef dat_t<uint32_t> A_t;
typedef dat_t<uint32_t> B_t;

const unsigned RATIO  = (sizeof(A_t)/sizeof(B_t));
const unsigned DEPTHA = SIZE/RATIO;
const unsigned DEPTHB = SIZE;

void dut(hls::stream<A_t> &inputStream, A_t *aximA, B_t *aximB,
         hls::stream<B_t> &outputStream);
