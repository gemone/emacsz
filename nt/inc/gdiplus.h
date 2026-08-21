/* Minimal C-compatible gdiplus.h for the MSVC-ABI build.

   The MSVC Windows SDK's <gdiplus.h> is C++-only (`namespace Gdiplus`,
   classes), so Emacs's C sources (w32fns/w32term/w32select/w32image)
   cannot include it when compiled with zig cc -target *-windows-msvc.
   mingw-w64 ships a C-compatible version; this header mirrors exactly
   the flat C surface those sources use (GpStatus, GpGraphics, GpImage,
   GpBitmap, the flat Flat* API types and enums), matching the
   declarations in src/w32gdiplus.h.  It is found BEFORE the SDK's copy
   via -Int/inc.

   The actual GDI+ functions are resolved at runtime via GetProcAddress
   (see src/w32image.c / w32gdiplus.h fn_* pointers), so no import
   library surface is needed here.  */

#ifndef EMACS_GDIPLUS_H_MINIMAL_C
#define EMACS_GDIPLUS_H_MINIMAL_C

#include <windows.h>
#include <objidl.h>		/* IStream */

typedef enum {
  Ok = 0,
  GenericError = 1,
  InvalidParameter = 2,
  OutOfMemory = 3,
  ObjectBusy = 4,
  InsufficientBuffer = 5,
  NotImplemented = 6,
  Win32Error = 7,
  WrongState = 8,
  Aborted = 9,
  FileNotFound = 10,
  ValueOverflow = 11,
  AccessDenied = 12,
  UnknownImageFormat = 13,
  FontFamilyNotFound = 14,
  FontStyleNotFound = 15,
  NotTrueTypeFont = 16,
  UnsupportedGdiplusVersion = 17,
  GdiplusNotInitialized = 18,
  PropertyNotFound = 19,
  PropertyNotSupported = 20,
  ProfileNotFound = 21
} Status;

typedef int GpStatus;		/* Status enum, Ok = 0 */

typedef struct GpGraphics GpGraphics;
/* GDI+ C flat API: GpBitmap IS-A GpImage (single inheritance via the
   same opaque handle in the flat API); model both as the same opaque
   tag so callers can pass GpBitmap* where GpImage* is expected, exactly
   like mingw-w64's C headers do.  */
typedef struct GpImage GpImage;
typedef GpImage GpBitmap;
typedef struct GpImageAttributes GpImageAttributes;

typedef DWORD ARGB;

/* PixelFormat (subset; Emacs only checks/uses these). */
typedef INT PixelFormat;
#define PixelFormatIndexed 0x00010000
#define PixelFormatGDI 0x00020000
#define PixelFormatAlpha 0x00040000
#define PixelFormatPAlpha 0x00080000
#define PixelFormatExtended 0x00100000
#define PixelFormatCanonical 0x00200000
#define PixelFormat32bppRGB 0x0022000E
#define PixelFormat32bppARGB 0x0026200A
#define PixelFormat32bppPARGB 0x0026200B

/* InterpolationMode (subset). */
typedef enum {
  InterpolationModeInvalid = -1,
  InterpolationModeDefault = 0,
  InterpolationModeLowQuality = 1,
  InterpolationModeHighQuality = 2,
  InterpolationModeBilinear = 3,
  InterpolationModeBicubic = 4,
  InterpolationModeNearestNeighbor = 5,
  InterpolationModeHighQualityBilinear = 6,
  InterpolationModeHighQualityBicubic = 7
} InterpolationMode;

/* RotateFlipType. */
typedef enum {
  RotateNoneFlipNone = 0,
  Rotate90FlipNone = 1,
  Rotate180FlipNone = 2,
  Rotate270FlipNone = 3,
  RotateNoneFlipX = 4,
  Rotate90FlipX = 5,
  Rotate180FlipX = 6,
  Rotate270FlipX = 7,
  RotateNoneFlipY = 8,
  Rotate90FlipY = 9,
  Rotate180FlipY = 10,
  Rotate270FlipY = 11,
  RotateNoneFlipXY = 12,
  Rotate90FlipXY = 13,
  Rotate180FlipXY = 14,
  Rotate270FlipXY = 15
} RotateFlipType;

/* Unit (subset). */
typedef enum {
  UnitWorld = 0,
  UnitDisplay = 1,
  UnitPixel = 2,
  UnitPoint = 3
} GpUnit;

/* DrawImageAbort / GetThumbnailImageAbort: plain callbacks. */
typedef BOOL (CALLBACK *DrawImageAbort) (void *);
typedef BOOL (CALLBACK *GetThumbnailImageAbort) (void *);

/* GdiplusStartup input/output structures (flat C, no C++ ctor). */
typedef struct {
  UINT32 GdiplusVersion;
  void *DebugEventCallback;
  BOOL SuppressBackgroundThread;
  BOOL SuppressExternalCodecs;
} GdiplusStartupInput;

typedef struct {
  UINT32 Hook;
  UINT32 Unhook;
} GdiplusStartupOutput;

/* PropertyItem (flat). */
typedef struct {
  PROPID id;
  ULONG length;
  WORD type;
  void *value;
} PropertyItem;

/* ImageCodecInfo (flat). */
typedef struct {
  GUID Clsid;
  GUID FormatID;
  const WCHAR *CodecName;
  const WCHAR *DllName;
  const WCHAR *FormatDescription;
  const WCHAR *FilenameExtension;
  const WCHAR *MimeType;
  DWORD Flags;
  DWORD Version;
  DWORD SigCount;
  DWORD SigSize;
  const BYTE *SigPattern;
  const BYTE *SigMask;
} ImageCodecInfo;

/* EncoderParameters (flat). */
typedef struct {
  UINT Count;
} EncoderParameters;

#define WINGDIPAPI
#define GDIPCONST const

/* PropertyTagXXX imaging constants (from the SDK's gdiplusimaging.h;
   mingw-w64's C gdiplus.h exposes them the same way).  */
#define PropertyTagFrameDelay 0x5100
#define PropertyTagGlobalPalette 0x5101
#define PropertyTagDimensionLength 0x5110
#define PropertyTagDimensionFrames 0x5111
#define PropertyTagByteOrder 0x5109
#define PropertyTagPixelFormat 0x510A
#define PropertyTagDNGVersion 0xC612
#define PropertyTagThumbData 0x501B

/* PropertyItem type codes.  */
#define PropertyTagTypeByte 1
#define PropertyTagTypeASCII 2
#define PropertyTagTypeShort 3
#define PropertyTagTypeLong 4
#define PropertyTagTypeRational 5
#define PropertyTagTypeUndefined 7
#define PropertyTagTypeSLONG 9
#define PropertyTagTypeSRational 10

#endif /* EMACS_GDIPLUS_H_MINIMAL_C */
