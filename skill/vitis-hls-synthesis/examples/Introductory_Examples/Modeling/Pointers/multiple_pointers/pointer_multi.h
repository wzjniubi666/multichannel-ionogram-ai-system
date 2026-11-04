

#ifndef _POINTER_MULTI_H_
#define _POINTER_MULTI_H_

#include <stdbool.h>
#include <stdio.h>

typedef unsigned char din_t;
typedef int dout_t;
typedef bool sel_t;

dout_t pointer_multi(bool sel, din_t pos);

#endif
