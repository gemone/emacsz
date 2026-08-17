/* Minimal tiffconf.h for building the vendored libtiff (tiff-4.7.0) with
   zig cc as a static lib (see build.zig's -Dwith-tiff).  Mirrors the
   tarball's tiffconf.h.in with the standard static build set: core codecs
   on, external codecs (JBIG/LERC/LZMA/WebP/ZSTD) off, matching the build
   source list and tif_config.h.  */

#ifndef TIFFCONF_H_MINIMAL_ZIG
#define TIFFCONF_H_MINIMAL_ZIG

#include <stdint.h>

typedef int8_t TIFF_INT8_T;
typedef uint8_t TIFF_UINT8_T;
typedef int16_t TIFF_INT16_T;
typedef uint16_t TIFF_UINT16_T;
typedef int32_t TIFF_INT32_T;
typedef uint32_t TIFF_UINT32_T;
typedef int64_t TIFF_INT64_T;
typedef uint64_t TIFF_UINT64_T;
/* Signed size type: ptrdiff_t is 64-bit on both Windows x64 ABIs (LLP64's
   long is only 32-bit, so use ptrdiff_t rather than long). */
#include <stddef.h>
typedef ptrdiff_t TIFF_SSIZE_T;
/* printf format for TIFF_SSIZE_T (ptrdiff_t on this config): "%td". */
#define TIFF_SSIZE_FORMAT "td"

/* Core codecs. */
#define CCITT_SUPPORT 1
#define PACKBITS_SUPPORT 1
#define LZW_SUPPORT 1
#define THUNDER_SUPPORT 1
#define NEXT_SUPPORT 1
#define LOGLUV_SUPPORT 1

/* MDI (Microsoft Document Imaging) -- pure stdio, portable. */
#define MDI_SUPPORT 1

/* Compression codecs that need external libs: OFF (not in the build). */
#undef ZIP_SUPPORT
#undef PIXARLOG_SUPPORT
#undef JPEG_SUPPORT
#undef JBIG_SUPPORT
#undef LZMA_SUPPORT
#undef ZSTD_SUPPORT
#undef LERC_SUPPORT
#undef WEBP_SUPPORT

/* Color space conversions used by tif_getimage (self-contained). */
#define COLORIMETRY_SUPPORT 1
#define YCBCR_SUPPORT 1
#define CMYK_SUPPORT 1
#define ICC_SUPPORT 1
#define PHOTOSHOP_SUPPORT 1
#define IPTC_SUPPORT 1

/* OJPEG is legacy and pulls jpeg internals: OFF. */
#undef OJPEG_SUPPORT

#endif /* TIFFCONF_H_MINIMAL_ZIG */
