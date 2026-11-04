
#include <stdlib.h>
#include "ecc_flags.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
using namespace std;

int main() {
    din_t in1[N];
    din_t in2[N];
    din_t output[N];
    const din_t Iter = 100;

    int i, retval = 0;
    ofstream FILE;

    // Create input data
    for (i = 0; i < N; ++i) {
        in1[i] = 1000 * i;
        in2[i] = 1000 * i;
        cout << in1[i] << endl;
        cout << in2[i] << endl;
    }
    // Save the results to a file
    FILE.open("result.dat");

    // Call the function

    ecc_flags(in1, in2, Iter, output);

    // Save output data
    for (i = 0; i < N; ++i) {
        cout << output[i] << endl;
        FILE << output[i] << endl;
    }
    FILE.close();

    // Compare the results file with the golden results
    retval = system("diff --brief -w result.dat result.golden.dat");
    if (retval != 0) {
        printf("Test failed  !!!\n");
        retval = 1;
    } else {
        printf("Test passed !\n");
    }

    // Return 0 if the test passes
    return retval;
}
