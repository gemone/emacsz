/* byteswap.h shim for MinGW (Zig ships no byteswap.h).

   Mirrors the gnulib byteswap module interface used by the tree
   (src/lisp.h, src/fringe.c, lib/md5.c, ...): bswap_16/32/64 as inline
   functions.  Clang provides the __builtin_bswap* family on every
   target, so no platform-specific intrinsics are needed.  */

#ifndef _GL_BYTESWAP_H
#define _GL_BYTESWAP_H 1

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

static inline uint_least16_t
bswap_16 (uint_least16_t x)
{
  return __builtin_bswap16 (x);
}

static inline uint_least32_t
bswap_32 (uint_least32_t x)
{
  return __builtin_bswap32 (x);
}

static inline uint_least64_t
bswap_64 (uint_least64_t x)
{
  return __builtin_bswap64 (x);
}

#ifdef __cplusplus
}
#endif

#endif /* _GL_BYTESWAP_H */
