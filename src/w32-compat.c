/* mingw compatibility helpers shared by the console AND GUI builds.

   getrandom over the Windows CSPRNG (fns.c secure-random, sysdep.c seed),
   set_binary_mode / close_stream (lib/binary-io.c only serves DJGPP/EMX
   and the gnulib-io package is not linked on Windows).  These used to
   live in w32-stubs.c; they moved here so the -Dgui build (which drops
   the GUI-module stubs in favor of the real modules) still links them.

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

#include <errno.h>
#include <io.h>		/* _setmode */
#include <stdbool.h>
#include <stdio.h>
#include <sys/types.h>

#include <windows.h>
#include <bcrypt.h>

#include "fpending.h"

ssize_t
getrandom (void *buffer, size_t length, unsigned int flags)
{
  (void) flags;
  if (BCryptGenRandom (NULL, buffer, length,
		       BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0)
    {
      errno = EIO;
      return -1;
    }
  return length;
}

int
set_binary_mode (int fd, int mode)
{
  return _setmode (fd, mode);
}

int
close_stream (FILE *stream)
{
  const bool some_pending = (__fpending (stream) != 0);
  const bool prev_fail = (ferror (stream) != 0);
  const bool fclose_fail = (fclose (stream) != 0);

  if (prev_fail || (fclose_fail && (some_pending || errno != EBADF)))
    {
      if (!prev_fail && !(fclose_fail && errno == 0))
	errno = fclose_fail ? errno : 0;
      return EOF;
    }
  return 0;
}
