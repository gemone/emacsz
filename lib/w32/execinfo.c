/* Minimal execinfo implementations for MinGW.

   glibc's backtrace family walks the call stack; on Windows the proper
   equivalent is RtlCaptureStackBackTrace, but Emacs's fatal-backtrace
   path degrades gracefully when no frames are reported, so these stubs
   keep the compile/link working for the native Windows milestone.  */

#include <config.h>

#include <execinfo.h>

int
backtrace (void **buffer, int size)
{
  (void) buffer;
  (void) size;
  return 0;
}

char **
backtrace_symbols (void *const *buffer, int size)
{
  (void) buffer;
  (void) size;
  return NULL;
}

void
backtrace_symbols_fd (void *const *buffer, int size, int fd)
{
  (void) buffer;
  (void) size;
  (void) fd;
}
