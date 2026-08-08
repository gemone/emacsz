/* Native-comp Zig path C stub (the `.zeln` subsystem).

Compiled ONLY when the build switch HAVE_NATIVE_COMP_ZIG is on
(conditional addCSourceFile in build.zig; it is never part of base_obj
in src/Makefile.in, which is the gccjit comp.c).  This is the M0/scaffold
stub: the real zunit serializer, freloc-manifest generator, and `.zeln`
loader/relocator land here in later milestones (plan section 7).  The
gccjit comp.c is a separate translation unit and is untouched.

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

#include "compz.h"

void
syms_of_compz (void)
{
  /* M0 stub: real zunit serializer + freloc manifest + .zeln loader
     land here in later milestones.  */
}
