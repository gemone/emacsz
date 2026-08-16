#ifndef _NT_STDBOOL_H_
#define _NT_STDBOOL_H_
/*
 * stdbool.h exists in GCC, but not in MSVC.
 *
 * ABI note: under `zig cc -target x86_64-windows-msvc`, __GNUC__ is NOT
 * defined (only _MSC_VER / __clang__ are), so the pre-C99 `#else` branch
 * below is what MSVC would hit.  build.zig forces `bool` to `signed char`
 * for the MSVC ABI (matching MinGW so Emacs's w32 code -- which mixes
 * `bool *` / `signed char *` -- compiles), so for MSVC we must NOT
 * `#define bool _Bool` here (that would clash).  Guard it out for _MSC_VER.
 */

#ifdef __GNUC__
# include_next <stdbool.h>
#else
# if defined _MSC_VER && !defined __MINGW32__
/* MSVC ABI: `bool` comes from build.zig's -Dbool=signed char; supply the
   CRT true/false and the _Bool spelling only.  The MSVC CRT <stdbool.h>
   would #define bool _Bool and clash, so we do not include_next it.  */
#  ifndef __cplusplus
#   ifndef false
#    define false 0
#   endif
#   ifndef true
#    define true 1
#   endif
#  endif
# else
# define _Bool signed char
# define bool _Bool
# define false 0
# define true 1
# endif
#endif

#endif	/* _NT_STDBOOL_H_ */
