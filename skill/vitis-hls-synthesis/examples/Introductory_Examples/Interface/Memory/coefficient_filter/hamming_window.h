
#ifndef HAMMING_WINDOW_H_
#define HAMMING_WINDOW_H_

#include <math.h>
#include <stdint.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// If WINDOW_LEN is not defined by the user, define a default value
#ifndef WINDOW_LEN
#define WINDOW_LEN 256
#endif
// If WIN_COEFF_FRACBITS not defined by user, set a default value
#ifndef WIN_COEFF_FRACBITS
#define WIN_COEFF_FRACBITS (14)
#endif
// Set the scale factor for the window coefficients
#define WIN_COEFF_SCALE ((float)(1 << WIN_COEFF_FRACBITS))

// This function applies an Hamming window function to the 'indata' buffer,
// returning the windowed data in 'outdata'.  The coefficients are 16-bit
// scaled integer, which may be interpreted as a signed fixed point format,
// with WIN_COEFF_FRACBITS bits after the binary point.
void hamming_window(int32_t outdata[], int16_t indata[]);

#endif // HAMMING_WINDOW_H_ not defined
