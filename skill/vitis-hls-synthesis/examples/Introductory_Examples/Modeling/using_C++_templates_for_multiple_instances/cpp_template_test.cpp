

#include "cpp_template.h"

int main() {
    int total_dut = 0;
    int retval = 0;

    // Call the DUT
    for (int i = 0; i < 10; i++) {
        cpp_template(i, &total_dut);
    }

    // Compare the results
    retval = (825 != total_dut);
    if (retval != 0) {
        printf("Test failed  !!!\n");
        retval = 1;
    } else {
        printf("Test passed !\n");
    }

    // Return 0 if the test passed
    return retval;
}
