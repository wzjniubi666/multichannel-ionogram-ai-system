
#define USE_WAIT
#include "ap_fixed.h"
#include "hls_fir.h"

const unsigned FIR_LENGTH   = 20;
const unsigned INPUT_WIDTH = 16;
const unsigned INPUT_FRACTIONAL_BITS = 0;
const unsigned OUTPUT_WIDTH = 24;
const unsigned OUTPUT_FRACTIONAL_BITS = 0;
const unsigned COEFF_WIDTH = 16;
const unsigned COEFF_FRACTIONAL_BITS = 0;
const unsigned COEFF_NUM = 7;
const unsigned COEFF_SETS = 3;
const unsigned INPUT_LENGTH = FIR_LENGTH;
const unsigned OUTPUT_LENGTH = FIR_LENGTH/2;
const unsigned CHAN_NUM = 1;

const unsigned total_num_coeff = COEFF_NUM * COEFF_SETS;  // 7 * 3 = 21

typedef ap_fixed<INPUT_WIDTH, INPUT_WIDTH - INPUT_FRACTIONAL_BITS> s_data_t;
typedef ap_fixed<OUTPUT_WIDTH, OUTPUT_WIDTH - OUTPUT_FRACTIONAL_BITS> m_data_t;
typedef ap_uint<8> config_t;

void fir_top(s_data_t in[INPUT_LENGTH], m_data_t out[OUTPUT_LENGTH], config_t* config);