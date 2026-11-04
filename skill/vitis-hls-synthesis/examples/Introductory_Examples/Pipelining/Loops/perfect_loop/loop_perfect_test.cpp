
#include <stdlib.h>
#include "loop_perfect.h"

int main() {
    din_t A[N];
    dout_t B[N];

    int i, retval = 0;
    ofstream FILE;

    for (i = 0; i < N; ++i) {
        A[i] = i;
    }
    // Save the results to a file
    FILE.open("result.dat");

    // Call the function
    loop_perfect(A, B);
    for (i = 0; i < N; ++i) {
        FILE << B[i] << endl;
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

    // Return 0 if the test passed
    return retval;
}
