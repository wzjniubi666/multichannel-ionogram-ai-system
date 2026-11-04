
#include "hamming_window.h" // Provides default WINDOW_LEN if not user defined

// Translation module function prototypes:
static void hamming_rom_init(int16_t rom_array[]);

// Function definitions:
void hamming_window(int32_t outdata[WINDOW_LEN], int16_t indata[WINDOW_LEN]) {
  static int16_t window_coeff[WINDOW_LEN];
  unsigned i;

  // In order to ensure that 'window_coeff' is inferred and properly
  // initialized as a ROM, it is recommended that the array initialization
  // be done in a sub-function with global (wrt this source file) scope.
  hamming_rom_init(window_coeff);
process_frame:
  for (i = 0; i < WINDOW_LEN; i++) {
#pragma HLS pipeline
    outdata[i] = (int32_t)window_coeff[i] * (int32_t)indata[i];
  }
}

// This initialization function will be optimized away during high level
// sythesis (HLS), resulting in the underlying memory being inferred as a ROM
// by RTL synthesis.
static void hamming_rom_init(int16_t rom_array[WINDOW_LEN]) {
  int i;
  for (i = 0; i < WINDOW_LEN; i++) {
    float real_val =
        0.54f - 0.46f * cos(2.0f * M_PI * i / (float)(WINDOW_LEN - 1));
    rom_array[i] = (int16_t)(round(WIN_COEFF_SCALE * real_val));
  }
}
