#ifndef NT_SYS_TYPES_H_INCLUDED
#define NT_SYS_TYPES_H_INCLUDED

/* Replacement <sys/types.h> for building GNU Emacs on Windows.

   Under the MinGW ABI the CRT's <sys/types.h> already defines the POSIX
   names Emacs's w32 code uses, so we just fall through to it.  The MSVC
   ABI CRT (zig cc -target *-windows-msvc) only defines the underscored
   _ino_t/_dev_t/_off_t (and conditionally ino_t/dev_t/off_t) and provides
   no pid_t / ssize_t / mode_t / _mode_t / sigset_t at all, so for that
   ABI we include the CRT's <sys/types.h> first and then supply the POSIX
   names with the same shapes Emacs's w32 code relies on (ms-w32.h's MSVC
   shim used to typedef the same set here; they are centralized in this
   header instead so gnulib/lib headers like lib/sys/stat.h and
   lib/unistd.h see them without pulling in ms-w32.h).

   The MSVC CRT spells them _pid_t / _ssize_t / _mode_t; Emacs's sources
   and gnulib headers use the POSIX spellings below, so map them to the
   CRT widths (SSIZE_T from <BaseTsd.h> is __int64 on x86_64).  */

#if defined _MSC_VER && !defined __MINGW32__
# include <corecrt.h>     /* _CRT_DECLARE_NONSTDC_NAMES machinery */
# include_next <sys/types.h>   /* CRT's _ino_t/_dev_t/_off_t */
# include <BaseTsd.h>     /* SSIZE_T */

# ifndef pid_t
typedef int pid_t;
# endif
# ifndef ssize_t
typedef SSIZE_T ssize_t;
# endif
# ifndef mode_t
typedef unsigned short mode_t;
# endif
# ifndef _mode_t
typedef unsigned short _mode_t;
# endif
# ifndef sigset_t
typedef unsigned int sigset_t;
# endif

/* The MSVC Windows SDK headers do not ship REPARSE_DATA_BUFFER (only
   MAXIMUM_REPARSE_DATA_BUFFER_SIZE / IO_REPARSE_TAG_*), while Emacs's w32
   code (written against mingw-w64's headers) resolves symlinks through it
   via FSCTL_GET_REPARSE_POINT in src/w32.c.  mingw-w64 supplies it; define
   it here (mirroring that layout) so src/w32.c needs no change.  The fields
   use base C types matching MSVC's LLP64 widths (ULONG=unsigned int,
   USHORT=unsigned short, UCHAR=unsigned char, WCHAR=wchar_t) so this stays
   valid before <windows.h> is reached, and it is harmless in every TU (only
   w32.c references the type).  Upstream-sync: drop if a future Windows SDK
   reintroduces it in user-mode headers.  */
# ifndef _REPARSE_DATA_BUFFER_DEFINED
#  define _REPARSE_DATA_BUFFER_DEFINED
typedef struct _REPARSE_DATA_BUFFER
{
  unsigned int ReparseTag;                 /* ULONG */
  unsigned short ReparseDataLength;        /* USHORT */
  unsigned short Reserved;                 /* USHORT */
  union
    {
      struct
	{
	  unsigned short SubstituteNameOffset;
	  unsigned short SubstituteNameLength;
	  unsigned short PrintNameOffset;
	  unsigned short PrintNameLength;
	  unsigned int Flags;               /* ULONG */
	  wchar_t PathBuffer[1];
	} SymbolicLinkReparseBuffer;
      struct
	{
	  unsigned short SubstituteNameOffset;
	  unsigned short SubstituteNameLength;
	  unsigned short PrintNameOffset;
	  unsigned short PrintNameLength;
	  wchar_t PathBuffer[1];
	} MountPointReparseBuffer;
      struct
	{
	  unsigned char DataBuffer[1];     /* UCHAR */
	} GenericReparseBuffer;
    };                                       /* anonymous, as mingw's */
} REPARSE_DATA_BUFFER, *PREPARSE_DATA_BUFFER;
# endif
#else
# include_next <sys/types.h>
#endif

#endif /* NT_SYS_TYPES_H_INCLUDED */
