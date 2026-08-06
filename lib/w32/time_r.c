/* MinGW time reentrancy and UTC conversions.

   The mingw-w64 CRT (as shipped with Zig 0.16.0) lacks the POSIX
   localtime_r/gmtime_r/timegm entry points; gnulib-time-rz uses them.
   Provide thin wrappers over the C11 _s variants and _mkgmtime.

Copyright (C) 2026 Free Software Foundation, Inc.

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

#include <config.h>

#include <errno.h>
#include <time.h>

/* glibc-style errno accessor used by the Zig packages.  */
int *
__errno_location (void)
{
  return &errno;
}

struct tm *
localtime_r (const time_t *timer, struct tm *tp)
{
  return localtime_s (tp, timer) == 0 ? tp : NULL;
}

struct tm *
gmtime_r (const time_t *timer, struct tm *tp)
{
  return gmtime_s (tp, timer) == 0 ? tp : NULL;
}

time_t
timegm (struct tm *tp)
{
  return _mkgmtime (tp);
}
