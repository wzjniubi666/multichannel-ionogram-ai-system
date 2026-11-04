


#include <stdlib.h>
#include "pointer_stream_better.h"

int main() {
  din_t d_i;
  dout_t d_o;
  int retval = 0;
  FILE *fp;

  // Open a file for the output results
  fp = fopen("result.dat", "w");
  fprintf(fp, "Din Dout\n");

  // Call the function to operate on the data
  for (d_i = 0; d_i < 4; d_i++) {
    pointer_stream_better(&d_o, &d_i);
    fprintf(fp, "%d   %d\n", d_i, d_o);
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
