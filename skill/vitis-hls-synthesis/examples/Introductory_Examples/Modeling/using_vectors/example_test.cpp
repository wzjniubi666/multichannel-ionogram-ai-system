

#include "example.h"
#include <iostream>
#include <vector>

int main(int, char**) {

    // The size of these vectors needs to match the depth of the adapter fifo
    // (specified via the depth option to interface pragma)
    std::vector<float16> lhs(32);
    std::vector<float16> rhs(32);
    std::vector<float16> res(32);

    float16 tmp1 = {3.2, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1,
                    3.2, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1};
    float16 tmp2 = {9.2, 8.1, 9.1, 6.1, 5.3, 3.2, 5.9, 3.8,
                    3.9, 9.1, 3.3, 4.5, 9.9, 2.1, 2.7, 6.1};
    for (int i = 0; i < NUM; i++) {
        lhs[i] = i % 2 ? tmp1 : tmp2;
        rhs[i] = i % 2 ? tmp2 : tmp1;
    }

    std::cout << "Size of res.data() = " << res.size() << std::endl;

    example(res.data(), lhs.data(), rhs.data(), 2);
    // example(res.data(), &tmp1, &tmp2, 1);

    std::cout << "The output value for res[0][1] should be 9.2 and is "
              << res[0][1] << std::endl;

    return 0;
}
