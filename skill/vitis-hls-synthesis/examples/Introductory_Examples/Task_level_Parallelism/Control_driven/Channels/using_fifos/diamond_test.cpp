
#include <stdlib.h>
#include "diamond.h"
#include <fstream>
#include <iostream>
using namespace std;

int main() {

    int totalNumWords = 512;
    std::vector<vecOf16Words> test(32);
    std::vector<vecOf16Words> outcome(32);

    int retval = 0;
    ofstream FILE;

    // Init test vector
    for (int i = 0; i < totalNumWords / 16; i++) {
        for (int j = 0; j < 16; j++) {
            test[i][j] = (data_t)j;
        }
    }
    cout << "Init: ";
    for (int i = 0; i < totalNumWords / 16; i++) {
        for (int j = 0; j < 16; j++) {
            cout << "  " << test[i][j];
        }
        cout << endl;
    }

    // Save the results to a file
    FILE.open("result.dat");

    // Executing the DUT thrice
    for (int iter = 0; iter < 3; iter++) {
        // Execute DUT
        diamond(test.data(), outcome.data(), totalNumWords / 16);

        // Display the results
        cout << "Outcome: ";
        for (int i = 0; i < totalNumWords / 16; i++) {
            for (int j = 0; j < 16; j++) {
                FILE << "  " << outcome[i][j];
            }
            FILE << endl;
        }
        FILE.close();
    }

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
