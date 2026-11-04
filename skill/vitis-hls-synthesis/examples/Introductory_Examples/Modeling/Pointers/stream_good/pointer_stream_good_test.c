
#include <stdlib.h>
#include "pointer_stream_good.h"

int main() {
  din_t d_i[4];
  dout_t d_o[4];
  int i, retval = 0;
  FILE *fp;

  // Create input data
  for (i = 0; i < 4; i++) {
    d_i[i] = i;
  }

  // Call the function to operate on the data
  pointer_stream_good(d_o, d_i);

  // Save the results to a file
  fp = fopen("result.dat", "w");
  fprintf(fp, "Din Dout\n");
  for (i = 0; i < 4; i++) {
    if (i < 2)
      fprintf(fp, "%d   %d\n", d_i[i], d_o[i]);
    else
      fprintf(fp, "%d \n", d_i[i]);
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
