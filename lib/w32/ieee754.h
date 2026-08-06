/* ieee754.h shim for MinGW (Zig ships no ieee754.h).

   glibc's <ieee754.h> exposes the bit layout of IEEE 754 doubles;
   src/lread.c and src/print.c use the union for NaN payloads and the
   infinity constant.  The layout below matches glibc's little-endian
   union (IEEE_FLOATING_POINT is true on mingw as well).  */

#ifndef _IEEE754_H
#define _IEEE754_H

union ieee754_double
  {
    double d;

    /* This is the IEEE 754 double-precision format.  */
    struct
      {
        unsigned int mantissa1:32;
        unsigned int mantissa0:20;
        unsigned int exponent:11;
        unsigned int negative:1;
      } ieee;

    /* This way of looking at the bits is useful for NaN handling.  */
    struct
      {
        unsigned int mantissa1:32;
        unsigned int mantissa0:19;
        unsigned int quiet_nan:1;
        unsigned int exponent:11;
        unsigned int negative:1;
      } ieee_nan;
  };

#endif /* _IEEE754_H */
