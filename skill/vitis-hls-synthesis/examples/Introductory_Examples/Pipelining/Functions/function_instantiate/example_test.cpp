
#include <stdlib.h>
#include "example.h"

int main() {

    int i, retval = 0;
    const char N = 10;
    char a, b, c;
    ofstream FILE;

    // Save the results to a file
    FILE.open("result.dat");

    for (i = 0; i < N; ++i) {
        // Call the function
        top(i, i, i, &a, &b, &c);
        FILE << (int)a << " " << (int)b << " " << (int)c << endl;
        cout << (int)a << " " << (int)b << " " << (int)c << endl;
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
