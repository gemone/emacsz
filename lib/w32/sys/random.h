/* sys/random.h shim for MinGW: declares getrandom, which
   lib/getrandom.c implements over BCryptGenRandom on Windows.  The
   committed gnulib lib/sys/random.h include_nexts here; it provides the
   GRND_* constants itself, so only the declaration is needed.  */

#ifndef _GL_W32_SYS_RANDOM_H
#define _GL_W32_SYS_RANDOM_H

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

ssize_t getrandom (void *buffer, size_t length, unsigned int flags);

#ifdef __cplusplus
}
#endif

#endif /* _GL_W32_SYS_RANDOM_H */
