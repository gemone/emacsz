/* Minimal libwebp config.h for the zig build (build.zig compiles
   libwebp with -DHAVE_CONFIG_H so cpu.h's WEBP_USE_* gating requires the
   explicit WEBP_HAVE_* macros below).  Every architecture-accelerated
   variant is OFF: the plain-C implementations cover all functionality
   (webp decode/encode/anim), and on an MSVC-ABI target the stock cpu.h
   would otherwise auto-enable SSE via WEBP_MSC_SSE41 and pull in
   *_sse*.c files whose always_inline intrinsics clang rejects.

   The real autotools config.h also sets HAVE_* for zlib/libpng/threads
   (all intentionally absent here) and package strings.  */

#ifndef EMACS_WEBP_CONFIG_H
#define EMACS_WEBP_CONFIG_H

/* Keep the well-known package metadata harmless.  */
#define PACKAGE "libwebp"
#define VERSION "1.5.0"

/* No acceleration variants, no threads, no external libs.  */
#undef WEBP_HAVE_SSE2
#undef WEBP_HAVE_SSE41
#undef WEBP_HAVE_NEON
#undef WEBP_HAVE_MIPS2
#undef WEBP_HAVE_MIPS32
#undef WEBP_HAVE_MSA
#undef WEBP_USE_THREADS
#undef WEBP_HAVE_THREADS
#undef HAVE_PTHREAD_H
#undef HAVE_ZLIB
#undef HAVE_LIBPNG

/* Deterministic printf formats (not used without stats).  */
#define PRINTF_FORMAT(x, y) __attribute__((format(printf, x, y)))

#endif /* EMACS_WEBP_CONFIG_H */