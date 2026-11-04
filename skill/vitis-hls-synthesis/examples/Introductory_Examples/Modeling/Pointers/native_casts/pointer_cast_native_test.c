


#include <stdlib.h>
#include "pointer_cast_native.h"

int main() {
  data_t din[N], idx, dout;

  int i, retval = 0;
  FILE *fp;

  // Create Input Data
  for (i = 0; i < N; ++i) {
    din[i] = i;
  }

  // Save the results to a file
  fp = fopen("result.dat", "w");

  // Call the function
  idx = 136;
  dout = pointer_cast_native(idx, din);

  fprintf(fp, "%d \n", dout);
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
