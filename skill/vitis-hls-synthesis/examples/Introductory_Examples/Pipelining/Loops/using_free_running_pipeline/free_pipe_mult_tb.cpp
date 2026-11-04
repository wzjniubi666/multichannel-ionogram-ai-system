
#include <stdlib.h>
#include "free_pipe_mult.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
using namespace std;

int main() {

    data_t Atest[SZ];
    data_t total;
    stream<data_t> strm;

    int retval = 0;
    ofstream FILE;

    // Create input data
    for (int i = 0; i < SZ; ++i) {
        Atest[i] = i;
        strm << i;
        cout << Atest[i] << endl;
    }
    // Save the results to a file
    FILE.open("result.dat");

    // Call the function
    free_pipe_mult(Atest, strm, total);

    // Save output data
    cout << "Result: " << total << endl;
    FILE << total << endl;
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
