
#include "test.h"

int main() {

    hls::stream<int> in;
    hls::stream<int> out;
	hls::ap_hs<int> n;
    int golden=0;
    for (int i = 0; i < N; i++)
    {
        n.write(i);
        in.write(i);
        golden += 2*i;
    }
    
    test(in, out, n);

    int sum = 0;
    for (int i = 0; i < N; i++)
        sum += out.read();

    if (sum != golden)
        return 1;
    return 0;
}
