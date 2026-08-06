/* execinfo.h shim for MinGW (Zig ships no execinfo.h).

   src/sysdep.c includes <execinfo.h> unconditionally for its fatal
   backtrace path.  The declarations below match glibc's interface; the
   Windows implementations in lib/w32/execinfo.c currently record no
   backtrace (upstream Windows Emacs has similarly reduced native
   backtrace support).  */

#ifndef _EXECINFO_H
#define _EXECINFO_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int backtrace (void **buffer, int size);
char **backtrace_symbols (void *const *buffer, int size);
void backtrace_symbols_fd (void *const *buffer, int size, int fd);

#ifdef __cplusplus
}
#endif

#endif /* _EXECINFO_H */
