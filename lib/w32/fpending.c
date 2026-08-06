/* __fpending for MinGW.

   gnulib's fpending.c only knows glibc's FILE internals.  mingw's
   stdio keeps the pending bytes elsewhere, so report none: close-stream
   then relies on ferror/fclose, which still detects write failures.  */

#include <config.h>

#include <stdio.h>

#include "fpending.h"

size_t
__fpending (FILE *fp)
{
  (void) fp;
  return 0;
}
