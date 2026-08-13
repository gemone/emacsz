/* environ accessor for the lib-src tools on macOS: Darwin does not
   declare environ in <unistd.h>, so the tools force this header via
   `-include` (mirrors src/callproc.c's crt_externs handling).  */

#ifndef _EMACS_TOOL_ENVIRON_H
#define _EMACS_TOOL_ENVIRON_H

#include <crt_externs.h>
#define environ (*_NSGetEnviron ())

#endif
