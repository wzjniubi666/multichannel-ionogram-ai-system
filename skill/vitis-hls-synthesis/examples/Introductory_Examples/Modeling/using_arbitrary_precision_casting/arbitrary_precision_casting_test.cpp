
#include <stdlib.h>
#include "arbitrary_precision_casting.h"

int main() {
    din_t A, B;
    dout_t RES;
    int i, retval = 0;
    ofstream FILE;

    // Save the results to a file
    FILE.open("result.dat");

    // Call the function
    A = 65536;
    B = 65536;
    for (i = 0; i < 20; ++i) {
        RES = arbitrary_precision_casting(A, B);
        FILE << RES << endl;
        A = A + 1024;
        B = B - 2047;
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
