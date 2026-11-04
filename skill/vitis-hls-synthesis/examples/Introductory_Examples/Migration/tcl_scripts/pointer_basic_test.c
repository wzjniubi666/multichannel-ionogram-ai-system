


#include <stdlib.h>
#include "pointer_basic.h"

int main() {
  dio_t d;
  int i, retval = 0;
  FILE *fp;

  // Save the results to a file
  fp = fopen("result.dat", "w");
  printf(" Din Dout\n");

  // Create input data
  // Call the function to operate on the data
  for (i = 0; i < 4; i++) {
    d = i;
    pointer_basic(&d);
    fprintf(fp, "%d \n", d);
    printf("  %d   %d\n", i, d);
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
