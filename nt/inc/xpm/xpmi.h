/* Case-forwarding shim: libXpm's src/simx.c includes "xpmi.h" (all
   lowercase) while the file on disk is XpmI.h; Windows hosts are
   case-insensitive so the upstream MSW build never noticed.  This
   directory sits on the include path BEFORE src/ (zig cc is strict
   about case).  */
#ifndef EMACS_XPMI_FORWARD
#define EMACS_XPMI_FORWARD
#include "XpmI.h"
#endif

/* simx.h (FOR_MSW) defines close/open/strdup etc. as CRT-underscore
   macros, which then leak into every OTHER header included afterwards
   (msvcrt/io.h already declares _close; a macro `close` breaks any
   later `close` use in image.c).  The tarball is immutable, so defuse
   the macros here: this header is included by XpmI.h consumers BEFORE
   any system header can be re-parsed, and the undef below runs after
   simx.h's defines (XpmI.h includes xpm.h which includes simx.h).
   Guarding with the simx include token ensures exact once-order.  */
#ifdef FOR_MSW
# undef close
# undef open
# undef fdopen
# undef strdup
# undef index
# undef rindex
# undef O_RDONLY
#endif
