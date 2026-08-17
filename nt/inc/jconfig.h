/* Minimal jconfig.h for building the vendored IJG libjpeg (jpeg-9f) with
   zig cc on Windows (both the GNU/MinGW and MSVC ABIs) and on any LLVM
   target.  The IJG tarball generates this file with configure; in jpeg-9
   the codec/feature switches live in jmorecfg.h (which #errors if they
   are ALSO defined here), so this file carries only the platform
   configuration.

   Part of the zig-build infrastructure (see build.zig's -Dwith-jpeg):
   fetched via build.zig.zon .jpeg_src, compiled with -Int/inc.  */

#ifndef JCONFIG_H_MINIMAL_ZIG
#define JCONFIG_H_MINIMAL_ZIG

#define JPEG_LIB_VERSION 90
#define LIBJPEG_TURBO_VERSION 0

#define HAVE_PROTOTYPES 1
#define HAVE_UNSIGNED_CHAR 1
#define HAVE_UNSIGNED_SHORT 1
/* stddef.h/stdlib.h exist on every Tier-1 target (LLVM provides them for
   the MSVC ABI too). */
#define HAVE_STDDEF_H 1
#define HAVE_STDLIB_H 1

/* jmemnobs.c (no backing-store manager) is in the build source list. */

#endif /* JCONFIG_H_MINIMAL_ZIG */
