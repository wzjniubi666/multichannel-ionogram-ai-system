

#include "fxp_sqrt_top.h"

out_data_t fxp_sqrt_top(in_data_t& in_val) {
    out_data_t result;
    fxp_sqrt(result, in_val);
    return result;
}
