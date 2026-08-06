/* alloca.h shim for MinGW (Zig ships no alloca.h).

   The committed gnulib lib/alloca.h (generated against glibc) always
   does `#include_next <alloca.h>` on _WIN32; this empty header gives
   that include_next a target.  gnulib then defines alloca as
   __builtin_alloca (or picks up the macro from <malloc.h> already
   included by src/ms-w32.h).  */
