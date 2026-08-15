/* Full gnulib getopt substitute for the macOS lib-src tools.

   lib/getopt.h is an include_next hybrid: it pulls in the SYSTEM
   <getopt.h> (renaming the system `struct option` out of the way) and
   layers gnulib's declarations on top.  That graft is sensitive to SDK
   drift in the system header -- Xcode 26.5's annotated declarations
   conflict with the layered ones, and on CI's SDK the interaction with
   __GETOPT_PREFIX=rpl_ left getopt1.c compiling with the renames and
   __getopt_argv_const both undefined (a hard parse error).

   This header lives in its own directory, registered on the tools'
   module include path BEFORE lib/, and the macOS tool flags drop -Ilib
   from the per-source set, so #include <getopt.h> resolves HERE: the
   full gnulib declarations with no include_next and no system getopt.h
   at all (the tools compile gnulib getopt.c/getopt1.c wholesale, and
   getopt-pfx-core renames the bare getopt too, so no system/rpl state
   can mix).

   config.h comes first because getopt-pfx-core pulls <unistd.h> on
   Darwin and the gnulib wrappers it reaches (sys/select.h,
   sys/types.h, ...) demand it.  */

#ifndef _GL_GETOPT_H
#define _GL_GETOPT_H 1

#include <config.h>
#include <getopt-cdefs.h>
#include <getopt-pfx-core.h>
#include <getopt-pfx-ext.h>

#endif /* _GL_GETOPT_H */
