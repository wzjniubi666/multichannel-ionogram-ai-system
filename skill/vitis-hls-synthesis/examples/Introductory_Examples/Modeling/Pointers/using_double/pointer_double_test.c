


#include <stdlib.h>
#include "pointer_double.h"

int main() {
  data_t data_o;

  int i, retval = 0;
  FILE *fp;

  // Save the results to a file
  fp = fopen("result.dat", "w");

  // Call the function for multiple transactions
  for (i = 0; i < 10; ++i) {
    int flag = i;
    data_o = pointer_double(i, -1, &flag);
    fprintf(fp, "%d \n", data_o);
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
