/* Darwin-only shims for glibc symbols the SDK lacks.  */

#ifdef DARWIN_OS

#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/types.h>

/* The Zig gnulib packages (fsusage, time-rz, tempname, careadlinkat,
   getloadavg, ...) reference the glibc-style errno accessor; Darwin
   exposes __error() instead.  */
int *
__errno_location (void)
{
  return __error ();
}

/* The secure-random callers (sysdep.c init_random, fns.c iv-auto) call
   getrandom(2); Darwin offers arc4random_buf instead.  */
ssize_t
getrandom (void *buffer, size_t length, unsigned int flags)
{
  (void) flags;
  arc4random_buf (buffer, length);
  return (ssize_t) length;
}

/* libc getloadavg(3) under a unique name, so the Zig
   gnulib-getloadavg package can call it without clashing with its own
   exported `getloadavg' symbol.  */
int
darwin_getloadavg (double *loadavg, int nelem)
{
  return getloadavg (loadavg, nelem);
}

#endif /* DARWIN_OS */
