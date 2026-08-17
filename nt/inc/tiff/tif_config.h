/* Minimal tif_config.h for building the vendored libtiff (tiff-4.7.0)
   with zig cc as a static lib (see build.zig's -Dwith-tiff).  The tarball
   generates this with autotools/cmake; the values below are the canonical
   static, no-extra-codecs set (CCITT + PackBits + LZW + Deflate only --
   no JBIG/LERC/LZMA/WebP/ZSTD, whose codecs are excluded from the build
   source list, and no Win32 fileio mmap paths).  */

#ifndef TIF_CONFIG_H_MINIMAL_ZIG
#define TIF_CONFIG_H_MINIMAL_ZIG

/* Codec support kept in sync with the build.zig source list. */
#define CCITT_SUPPORT 1
#undef LERC_SUPPORT
#undef LZMA_SUPPORT
#undef WEBP_SUPPORT
#undef ZSTD_SUPPORT
#undef CXX_SUPPORT

/* Hosted-C headers every Tier-1 LLVM target provides.  inttypes.h supplies
   the PRIu64 & friends the libtiff sources use in diagnostics. */
#include <inttypes.h>
#define HAVE_ASSERT_H 1
#define HAVE_FCNTL_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_STRINGS_H 1
#define HAVE_UNISTD_H 1 /* MinGW/glibc; the MSVC ABI path defines it out below */
#define HAVE_SNPRINTF 1
#define HAVE_FSEEKO 1
#define SIZEOF_SIZE_T 8

#ifdef _MSC_VER
/* The MSVC CRT: no unistd.h / io.h setmode semantics differ; keep the
   portable stdio paths. */
# undef HAVE_UNISTD_H
# define HAVE_IO_H 1
# define HAVE_SETMODE 1
# define USE_WIN32_FILEIO 1
#endif

#define STRIP_SIZE_DEFAULT 8192
#define TIFF_MAX_DIR_COUNT 1048576

#define PACKAGE "tiff"
#define PACKAGE_NAME "LibTIFF"
#define PACKAGE_VERSION "4.7.0"

#endif /* TIF_CONFIG_H_MINIMAL_ZIG */
