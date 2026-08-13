/* nl_langinfo for MinGW (no <langinfo.h> and no nl_langinfo in the CRT).

   etags's gnulib regex calls nl_langinfo (CODESET) to pick the locale
   codeset for the regex locale tables.  etags is ASCII-oriented, so a
   fixed "UTF-8" reply is enough.  */

#include <config.h>

typedef int nl_item;
#define CODESET 0

char *
nl_langinfo (nl_item item)
{
  switch (item)
    {
    case CODESET:
      return (char *) "UTF-8";
    default:
      return (char *) "";
    }
}
