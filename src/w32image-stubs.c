/* No-op w32image shims for the MSVC-ABI GUI build.

   The real src/w32image.c (GDI+ native image API, HAVE_NATIVE_IMAGE_API)
   includes <gdiplus.h>, which in the MSVC Windows SDK is a C++-only
   header (minwg-w64's is C).  The vendored png/jpeg/tiff decoders
   (EMACS_STATIC_IMAGE_LIBS) already cover image support, so the MSVC GUI
   build links these no-op syms_of/globals_of hooks instead; the GDI+
   fn_* pointers stay NULL and image_can_use_native_api is never
   consulted because HAVE_NATIVE_IMAGE_API is not defined.

Copyright (C) 2026 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.  */

#include <config.h>

#include "lisp.h"
#include "w32common.h"		/* DEF_DLL_FN machinery types */
#include "w32gdiplus.h"

/* The GDI+ lifecycle/function pointers live in w32image.c normally; on
   the MSVC ABI that file is replaced by these no-ops (its <gdiplus.h>
   is C++-only there).  w32term.c/w32select.c guard every use behind
   w32_gdiplus_startup(), which returns false here, so the NULL pointers
   are never called.  */
GdiplusStartup_Proc fn_GdiplusStartup;
GdiplusShutdown_Proc fn_GdiplusShutdown;
GdipCreateFromHDC_Proc fn_GdipCreateFromHDC;
GdipDeleteGraphics_Proc fn_GdipDeleteGraphics;
GdipGetPropertyItemSize_Proc fn_GdipGetPropertyItemSize;
GdipGetPropertyItem_Proc fn_GdipGetPropertyItem;
GdipImageGetFrameDimensionsCount_Proc fn_GdipImageGetFrameDimensionsCount;
GdipImageGetFrameDimensionsList_Proc fn_GdipImageGetFrameDimensionsList;
GdipImageGetFrameCount_Proc fn_GdipImageGetFrameCount;
GdipImageSelectActiveFrame_Proc fn_GdipImageSelectActiveFrame;
GdipCreateBitmapFromFile_Proc fn_GdipCreateBitmapFromFile;
GdipCreateBitmapFromStream_Proc fn_GdipCreateBitmapFromStream;
GdipCreateBitmapFromScan0_Proc fn_GdipCreateBitmapFromScan0;
GdipCreateBitmapFromHBITMAP_Proc fn_GdipCreateBitmapFromHBITMAP;
GdipSetInterpolationMode_Proc fn_GdipSetInterpolationMode;
GdipDrawImageRectRectI_Proc fn_GdipDrawImageRectRectI;
GdipCreateHBITMAPFromBitmap_Proc fn_GdipCreateHBITMAPFromBitmap;
GdipDisposeImage_Proc fn_GdipDisposeImage;
GdipGetImageHeight_Proc fn_GdipGetImageHeight;
GdipGetImageWidth_Proc fn_GdipGetImageWidth;
GdipGetImageEncodersSize_Proc fn_GdipGetImageEncodersSize;
GdipGetImageEncoders_Proc fn_GdipGetImageEncoders;
GdipLoadImageFromFile_Proc fn_GdipLoadImageFromFile;
GdipGetImageThumbnail_Proc fn_GdipGetImageThumbnail;
GdipSaveImageToFile_Proc fn_GdipSaveImageToFile;
GdipImageRotateFlip_Proc fn_GdipImageRotateFlip;

void
w32_gdiplus_shutdown (void)
{
}

bool
w32_gdiplus_startup (void)
{
  /* No GDI+ on this build: callers take their fallback paths.  */
  return false;
}

int
w32_gdip_export_frame (HWND hwnd, Lisp_Object file, CLSID *clsid)
{
  (void) hwnd; (void) file; (void) clsid;
  return -1;
}

int
w32_gdip_get_encoder_clsid (const char *type, CLSID *clsid)
{
  (void) type; (void) clsid;
  return -1;
}

void syms_of_w32image (void) {}
void globals_of_w32image (void) {}
