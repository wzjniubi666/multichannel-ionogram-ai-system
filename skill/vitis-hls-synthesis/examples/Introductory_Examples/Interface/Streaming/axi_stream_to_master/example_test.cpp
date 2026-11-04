

#include "example.h"

int main() {
    int err = 0;
    ap_uint<64> out_t[1024];
    hls::stream<trans_pkt> inStream_t;
    trans_pkt dataStream_t;

    for (int i = 0; i < 1024; i++) {
        dataStream_t.data = i;
        dataStream_t.keep = -1;
        if (i < 1023) {
            dataStream_t.last = 0;
        } else {
            dataStream_t.last = 1;
        }
        inStream_t.write(dataStream_t);
    }

    example(inStream_t, out_t);
    return err;
}
