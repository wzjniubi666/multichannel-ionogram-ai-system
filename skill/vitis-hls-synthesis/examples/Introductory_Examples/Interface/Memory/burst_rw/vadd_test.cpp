
#include <vector>
#include <iostream>
#include "vadd.h"

int main() {

    int size = DATA_SIZE;
    int inc_value = INCR_VALUE;
    // Allocate Memory in Host Memory
    size_t vector_size_bytes = sizeof(int) * size;
    std::vector<int> source_inout(size);
    std::vector<int> source_sw_results(size);

    // Create the test data and Software Result
    for (int i = 0; i < size; i++) {
        source_inout[i] = i;
        source_sw_results[i] = i + inc_value;
    }

    vadd(source_inout.data(), size, inc_value);	

    // Compare the results of the Device to the simulation
    int match = 0;
    for (int i = 0; i < size; i++) {
        if (source_inout[i] != source_sw_results[i]) {
            std::cout << "Error: Result mismatch" << std::endl;
            std::cout << "i = " << i << " CPU result = " << source_sw_results[i]
                      << " Device result = " << source_inout[i] << std::endl;
            match = 1;
            break;
        } else {
            std::cout << source_inout[i] << " ";
            if (((i + 1) % 16) == 0) std::cout << std::endl;
        }
    }

    std::cout << "TEST " << (match ? "FAILED" : "PASSED") << std::endl;
    return (match ? EXIT_FAILURE : EXIT_SUCCESS);
}
