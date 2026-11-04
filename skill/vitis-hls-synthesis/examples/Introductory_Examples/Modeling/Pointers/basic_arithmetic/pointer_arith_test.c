
#include <stdlib.h>
#include "pointer_arith.h"

int main() {
  dio_t d[5], ref[5];
  int i, retval = 0;
  FILE *fp;

  // Create input data
  for (i = 0; i < 5; i++) {
    d[i] = i;
    ref[i] = i;
  }

  // Call the function to operate on the data
  pointer_arith(d);

  // Save the results to a file
  fp = fopen("result.dat", "w");
  printf(" Din Dout\n");
  for (i = 0; i < 4; i++) {
    fprintf(fp, "%d \n", d[i]);
    printf("  %d   %d\n", ref[i], d[i]);
  }
  fclose(fp);

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
