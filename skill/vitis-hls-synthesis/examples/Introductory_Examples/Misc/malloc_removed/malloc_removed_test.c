


#include <stdlib.h>
#include "malloc_removed.h"

int main() {
  din_t A[N];
  dout_t accum;

  int i, retval = 0;
  FILE *fp;

  for (i = 0; i < N; ++i) {
    A[i] = i + 200;
  }
  // Save the results to a file
  fp = fopen("result.dat", "w");

  // Call the function
  for (i = 0; i < N; ++i) {
    accum = malloc_removed(A, i);
    fprintf(fp, "%lld \n", (long long)accum);
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
