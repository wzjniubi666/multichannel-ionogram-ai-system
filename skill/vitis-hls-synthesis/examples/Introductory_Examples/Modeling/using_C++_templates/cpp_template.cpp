

#include "cpp_template.h"

// Tail recursive call
template <data_t N> struct fibon_s {
    template <typename T> static T fibon_f(T a, T b) {
        return fibon_s<N - 1>::fibon_f(b, (a + b));
    }
};

// Termination condition
template <> struct fibon_s<1> {
    template <typename T> static T fibon_f(T a, T b) { return b; }
};

void cpp_template(data_t a, data_t b, data_t& dout) {
    dout = fibon_s<FIB_N>::fibon_f(a, b);
}
