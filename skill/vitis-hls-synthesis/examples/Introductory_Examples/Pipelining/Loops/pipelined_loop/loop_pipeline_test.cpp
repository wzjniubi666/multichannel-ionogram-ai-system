
#include <stdlib.h>
#include "loop_pipeline.h"

int main() {
    din_t A[N];
    dout_t accum;

    int i, j, retval = 0;
    ofstream FILE;

    // Create input data
    for (i = 0; i < N; ++i) {
        A[i] = i;
    }
    // Save the results to a file
    FILE.open("result.dat");

    // Call the function
    for (j = 0; j < NUM_TRANS; ++j) {
        accum = loop_pipeline(A);
        FILE << accum << endl;
        // New input data
        for (i = 0; i < N; ++i) {
            A[i] = A[i] + N;
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

    // Return 0 if the test
    return retval;
}
