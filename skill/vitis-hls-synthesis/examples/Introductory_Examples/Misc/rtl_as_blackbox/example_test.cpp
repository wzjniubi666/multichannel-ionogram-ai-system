
#include <stdlib.h>
#include "example.h"
#include <iostream>

int main() {

    data_t sum;
    int i, j, retval = 0;
    ofstream FILE;

    // Save the results to a file
    FILE.open("result.dat");

    // Create input data
    for (i = 0; i < 10; ++i) {
        example(i, i - 10, i + 10, i - 20, i, 2 * i, 3 * i, 4 * i, sum);
        cout << " sum " << (int)sum << endl;
        FILE << sum << endl;
    }

    // Closing FILE
    FILE.close();

    // Compare the results file with the golden results
    retval = system("diff --brief -w result.dat result.golden.dat");
    if (retval != 0) {
        cout << "Test failed  !!!" << endl;
        retval = 1;
    } else {
        cout << "Test passed !" << endl;
    }

    // Return 0 if the test passes
    return retval;
}
