/* stdint.h shim for MinGW: C23 *WIDTH macros.

   Zig's mingw <stdint.h> only defines the __X_WIDTH__ spellings, while
   Emacs sources use the C23 SIZE_WIDTH / UINTPTR_WIDTH / PTRDIFF_WIDTH
   etc. directly (src/lisp.h, lib/rawmemchr.c).  glibc provides these in
   <stdint.h>; define them here before handing off to the real header.
   The integer width macros from <limits.h> are already supplied by the
   committed gnulib lib/limits.h.  Values match mingw's own
   __PTRDIFF_WIDTH__ etc. on the LLP64 ABI.  */

#ifndef _GL_W32_STDINT_H
#define _GL_W32_STDINT_H

#define PTRDIFF_WIDTH 64
#define SIZE_WIDTH 64
#define INTPTR_WIDTH 64
#define UINTPTR_WIDTH 64
#define INTMAX_WIDTH 64
#define UINTMAX_WIDTH 64
#define INT_LEAST8_WIDTH 8
#define INT_LEAST16_WIDTH 16
#define INT_LEAST32_WIDTH 32
#define INT_LEAST64_WIDTH 64
#define UINT_LEAST8_WIDTH 8
#define UINT_LEAST16_WIDTH 16
#define UINT_LEAST32_WIDTH 32
#define UINT_LEAST64_WIDTH 64
#define INT_FAST8_WIDTH 8
#define INT_FAST16_WIDTH 32
#define INT_FAST32_WIDTH 32
#define INT_FAST64_WIDTH 64
#define UINT_FAST8_WIDTH 8
#define UINT_FAST16_WIDTH 32
#define UINT_FAST32_WIDTH 32
#define UINT_FAST64_WIDTH 64
#define WCHAR_WIDTH 16
#define WINT_WIDTH 16
#define SIG_ATOMIC_WIDTH 32

#include_next <stdint.h>

#endif /* _GL_W32_STDINT_H */
