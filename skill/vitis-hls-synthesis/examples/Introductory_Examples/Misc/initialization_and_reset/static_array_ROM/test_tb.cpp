
#include "test.h"

int main() {
    int j = 5;
    int ret = test(j);
    int golden = 9;
    int result = 0;
    if (ret == golden) {
        printf("Test passed!\n");
    } else {
        printf("Test failed!\n");
        result = 1;
    }
    return result;
}
