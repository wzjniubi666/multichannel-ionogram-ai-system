


#include <stdlib.h>
#include "pointer_multi.h"

int main() {
  din_t idx = 0;
  sel_t mem_sel = true;
  dout_t dout;

  int i, retval = 0;
  FILE *fp;

  // Save the results to a file
  fp = fopen("result.dat", "w");

  // Call the function
  // Create Input Data
  for (i = 0; i < 8; ++i) {
    dout = pointer_multi(mem_sel, idx);
    fprintf(fp, "%d \n", dout);
    idx = idx + 1;
    mem_sel = !mem_sel;
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
