
#include <stdlib.h>
#include "cpp_template.h"

int main() {
    ofstream result;
    data_t input, output;
    int retval = 0;

    result.open("result.dat");
    // Persistent manipulators
    result << right << fixed << setbase(10) << setprecision(10);

    for (data_t i = 0; i <= 250; i++) {
        input = i;
        cpp_template(input, input + 1, output);

        result << setw(10) << i;
        result << setw(20) << input;
        result << setw(20) << input + 1;
        result << setw(20) << output;
        result << endl;
    }
    result.close();

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
