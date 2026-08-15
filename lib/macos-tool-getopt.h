/* Full gnulib getopt substitute for the macOS lib-src tools, forced
   before every tool source via -include (the same pattern as
   macos-environ.h).

   lib/getopt.h is an include_next hybrid: it pulls in the SYSTEM
   <getopt.h> (renaming the system `struct option` out of the way) and
   then layers gnulib's declarations on top.  That graft is sensitive to
   SDK drift in the system header -- Xcode 26.5's annotated declarations
   conflict with the layered ones, and on other SDKs the interaction
   with __GETOPT_PREFIX=rpl_ left getopt1.c compiling with the renames
   and __getopt_argv_const undefined (a hard parse error).  The tools
   compile gnulib getopt.c/getopt1.c wholesale, so the system getopt is
   never referenced: pre-defining lib/getopt.h's guard makes every later
   #include <getopt.h> a no-op, and the pfx chain below supplies the
   full prefixed declarations (getopt-pfx-core also renames the bare
   getopt, so no system/rpl state can mix).  The angle includes resolve
   against -Ilib; this file's directory has nothing to shadow.  */

#ifndef _GL_GETOPT_H
#define _GL_GETOPT_H 1

/* getopt-pfx-core.h pulls <unistd.h> on Darwin, and the gnulib wrappers
   it reaches (sys/select.h, sys/types.h, ...) require config.h FIRST;
   a -include runs before the including source's own config.h include,
   so provide it here.  */
#include <config.h>

#include <getopt-cdefs.h>
#include <getopt-pfx-core.h>
#include <getopt-pfx-ext.h>

#endif /* _GL_GETOPT_H */
