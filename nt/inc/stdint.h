/* Replacement stdint.h file for building GNU Emacs on Windows.

Copyright (C) 2011-2026 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.  */

#ifndef _NT_STDINT_H_
#define _NT_STDINT_H_

#ifdef __GNUC__
# include_next <stdint.h> /* use stdint.h if available */
#else	/* !__GNUC__ */

/* MSVC ABI (zig cc -target *-windows-msvc defines _MSC_VER, not
   __GNUC__, so this branch is reached).  The bundled stdint.h that zig's
   clang ships is complete and correctly sized for the LLP64 MSVC ABI
   (int64_t/uint64_t are 64-bit, long stays 32-bit, SIZE_MAX/PTRDIFF_MAX
   fit __int64, INT32_MIN/MAX, UINT32_MAX, INT_LEAST32_MIN/MAX etc. are
   all present).  Just fall through to it via include_next instead of
   hand-rolling a partial reimplementation that used to shadow the real
   stdint.h and left uint8_t/int32_t/int64_t/uintptr_t and the *_MAX/_MIN
   macros undefined across the tree-sitter/sha3/u64 consumers.  The
   #ifndef SIZE_MAX/PTRDIFF_MAX guards below are then no-ops (the bundled
   header defines them), but are kept as a safety net.  */
# include_next <stdint.h>

#endif	/* !__GNUC__ */

#endif /* _NT_STDINT_H_ */
