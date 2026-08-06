/* stpcpy for MinGW (UCRT provides only strcpy/_strcpy).

   glibc's stpcpy copies SRC into DEST and returns the pointer to the
   terminating NUL, which strcpy callers then use as the new end.
   Implemented as a tiny loop; declared from lib/string.h on WINDOWSNT.  */

#include <config.h>

#include <string.h>

char *
stpcpy (char *dest, const char *src)
{
  char *d = dest;
  const char *s = src;

  do
    *d++ = *s;
  while (*s++ != '\0');

  return d - 1;
}
