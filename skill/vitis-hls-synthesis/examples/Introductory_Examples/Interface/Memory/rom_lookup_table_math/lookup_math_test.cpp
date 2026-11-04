
#include <stdlib.h>
#include "lookup_math.h"

int main() {
    din1_t data1_i = 1;
    din2_t data2_i = 100;
    dout_t data_o;

    int i, retval = 0;
    ofstream FILE;

    // Save the results to a file
    FILE.open("result.dat");

    // Call the function for multiple transactions
    for (i = 0; i < 64; i++) {
        data_o = lookup_math(data1_i, data2_i);
        FILE << data_o << endl;
        data1_i = data1_i + 1;
        data2_i = data2_i + 1;
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

    // Return 0 if the test passes
    return retval;
}
