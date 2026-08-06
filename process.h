/* process.h shim at the repo root.

   Zig's mingw <pthread.h> includes <process.h> (angle brackets), which
   would otherwise resolve to src/process.h via -Isrc and get dragged
   into the preprocessor before lisp.h is complete.  Emacs's own
   sources include "process.h" quoted, which always finds src/process.h
   first (the including file's directory), so only the system-header
   angle-bracket includes land here.  src/ms-w32.h declares _getpid and
   _execvp itself; the declarations below cover the rest of the classic
   <process.h> API for anything that includes it directly.  */

#ifndef EMACS_W32_PROCESS_SHIM_H
#define EMACS_W32_PROCESS_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int _getpid (void);
intptr_t _beginthread (void (__cdecl *start_address) (void *), unsigned stack_size, void *arglist);
void _endthread (void);
uintptr_t _beginthreadex (void *security, unsigned stack_size,
                          unsigned (__stdcall *start_address) (void *),
                          void *arglist, unsigned initflag, unsigned *thrdaddr);
void _endthreadex (unsigned retval);
int _cwait (int *termstat, intptr_t proc_handle, int action);

#ifdef __cplusplus
}
#endif

#endif /* EMACS_W32_PROCESS_SHIM_H */
