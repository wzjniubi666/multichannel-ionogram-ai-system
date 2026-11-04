
#include <stdlib.h>
#include "diamond.h"
#include <fstream>
#include <iostream>
using namespace std;

int main() {

    hls::stream<data_t> test;
    hls::stream<data_t> outcome;

    int retval = 0;
    ofstream FILE;

    // Save the results to a file
    FILE.open("result.dat");

    // Executing the DUT thrice
    for (int iter = 0; iter < 3; iter++) {

        // Init test vector
        for (int i = 0; i < N; i++) {
            test.write(i);
        }

        // Execute DUT
        diamond(test, outcome);

        // Display the results
        for (int i = 0; i < N; i++) {
            data_t outp = outcome.read();
            cout << "Series " << iter;
            cout << " Outcome: " << (int)outp << endl;
            FILE << (int)outp << endl;
        }
    }

    FILE.close();

    // Compare the results file with the golden results
    retval = system("diff --brief -w result.dat result.golden.dat");
    if (retval != 0) {
        cout << "Test failed  !!!" << endl;
        retval = 1;
    } else {
        cout << "Test passed !" << endl;
    }

    // Return 0 if the test passed
    return retval;
}
