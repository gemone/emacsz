/* Darwin-only shims for glibc symbols the SDK lacks.  */

#include <config.h>

#ifdef DARWIN_OS

#include <errno.h>
#include <dlfcn.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>

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

/* Provide `getloadavg' for the C callers.  The executable defines this
   symbol itself, so a direct call would bind to this definition and
   recurse; dlsym(RTLD_NEXT) skips the main image and reaches
   libSystem's getloadavg(3).  */
int
getloadavg (double *loadavg, int nelem)
{
  static int (*volatile libc_getloadavg) (double *, int);
  if (!libc_getloadavg)
    libc_getloadavg = (int (*) (double *, int)) dlsym (RTLD_NEXT, "getloadavg");
  if (!libc_getloadavg)
    return -1;
  return libc_getloadavg (loadavg, nelem);
}

/* Provide `num_processors' for the C callers; the Linux-only Zig
   gnulib-nproc package does not export it on Darwin.  The query
   constants match lib/nproc.c: NPROC_ALL=0, NPROC_CURRENT=1,
   NPROC_CURRENT_OVERRIDABLE=2.  */
unsigned long
num_processors (int query)
{
  long n = sysconf (query == 0 ? _SC_NPROCESSORS_CONF
		     : _SC_NPROCESSORS_ONLN);
  return 0 < n ? (unsigned long) n : 1;
}

#endif /* DARWIN_OS */
