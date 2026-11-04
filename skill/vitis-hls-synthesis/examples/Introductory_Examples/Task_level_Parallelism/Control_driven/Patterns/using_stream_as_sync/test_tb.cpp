

#include "test.h"
#include <iostream>

int main()
{

    int A[N][N];
    hls::stream<int> in;
    hls::stream<int> out;

    // Create input stream data
    for (unsigned int i=0; i < N; ++i) {
        for (unsigned int j=0; j < N; ++j) {
            std::cout << "TB: Writing (" << i << "," << j << ") = " << i+j << std::endl;
            in << i+j;
        }
    }

    // Instantiate the top level function
    dut(in, A, out);

    // Check output stream data
    unsigned errors = 0;
    for (unsigned i=0; i < N; ++i) {
        for (unsigned j=0; j < N; ++j) {
            unsigned temp = out.read();
            if (temp != i+j) {
                std::cout << "ERROR: A[" << i << "][" << j << "] does not match" << std::endl;
                errors++;
            }
        }
    }

    if (errors) {
        std::cout << "FAILURE" << std::endl;
        return 1;
    }
    else {
        std::cout << "SUCCESS" << std::endl;
        return 0;
    }
}
