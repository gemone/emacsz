/* file_has_acl stub for lib-src tools on platforms without the POSIX-ACL
   stack (macOS and static musl: no libacl, and the
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
