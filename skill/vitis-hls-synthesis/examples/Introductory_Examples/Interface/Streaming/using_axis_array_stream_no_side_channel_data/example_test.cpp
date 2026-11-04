

#include <stdio.h>

void example(int A[50], int B[50]);

int main() {
    int i;
    int A[50];
    int B[50];
    int C[50];

    printf("HLS AXI-Stream no side-channel data example\n");
    // Put data into A
    for (i = 0; i < 50; i++) {
        A[i] = i;
    }

    // Call the hardware function
    example(A, B);

    // Run a software version of the hardware function to validate results
    for (i = 0; i < 50; i++) {
        C[i] = A[i] + 5;
    }

    // Compare results
    for (i = 0; i < 50; i++) {
        if (B[i] != C[i]) {
            printf("ERROR HW and SW results mismatch\n");
            return 1;
        }
    }
    printf("Success HW and SW results match\n");
    return 0;
}
