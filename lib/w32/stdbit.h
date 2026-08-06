/* stdbit.h shim for MinGW (Zig ships no C23 <stdbit.h>).

   The committed gnulib lib/stdbit.h (generated against glibc) does an
   unconditional `#include_next <stdbit.h>`; this empty header satisfies
   it without defining __STDBIT_H, so the gnulib implementation that
   follows the include_next block (stdc_bit_width, stdc_count_ones,
   stdc_leading_zeros, stdc_trailing_zeros, ...) becomes active.  */
