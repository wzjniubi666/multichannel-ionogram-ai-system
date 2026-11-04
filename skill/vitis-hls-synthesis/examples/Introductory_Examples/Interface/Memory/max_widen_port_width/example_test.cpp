

#include "example.h"
using namespace std;

int main() {
    int in[N], res[N];
    for (size_t i = 0; i < N; ++i)
        in[i] = i;

    example(in, res);

    size_t err = 0;
    for (int i = 0; i < N; ++i)
        if (res[i] != i + 100)
            return EXIT_FAILURE;

    cout << "Test passed.\n";
    return EXIT_SUCCESS;
}
