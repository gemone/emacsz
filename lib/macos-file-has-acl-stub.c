/* file_has_acl stub for the lib-src tools on macOS: the zig tools do
   not build gnulib's POSIX-ACL stack there (no libacl, and the
   committed Linux config's HAVE_ACL_LIBACL_H would pull <acl/libacl.h>).
   Returning 0 (no ACL) matches "ACL support unavailable".  */

#include <config.h>
#include <sys/stat.h>

int
file_has_acl (char const *name, struct stat const *st)
{
  (void) name;
  (void) st;
  return 0;
}
