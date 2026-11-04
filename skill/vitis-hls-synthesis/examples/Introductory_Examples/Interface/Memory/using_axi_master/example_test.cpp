

#include <stdio.h>

void example(volatile int* a);

int main() {
    int i;
    int A[50];
    int B[50];

    printf("HLS AXI-Stream no side-channel data example\n");
    // Put data into A
    for (i = 0; i < 50; i++) {
        A[i] = i;
    }

    // Call the hardware function
    example(A);

    // Run a software version of the hardware function to validate results
    for (i = 0; i < 50; i++) {
        B[i] = i + 100;
    }

    // Compare results
    for (i = 0; i < 50; i++) {
        if (B[i] != A[i]) {
            printf("i = %d A = %d B= %d\n", i, A[i], B[i]);
            printf("ERROR HW and SW results mismatch\n");
            return 1;
        }
    }
    printf("Success HW and SW results match\n");
    return 0;
}
