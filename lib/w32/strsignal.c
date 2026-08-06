/* strsignal for MinGW (mingw-w64 does not provide it).

   A small signal-name table in the style of gnulib's strsignal;
   unknown signals fall back to "Unknown signal <n>".  Declared from
   lib/string.h on WINDOWSNT.  */

#include <config.h>

#include <stdio.h>
#include <string.h>

char *
strsignal (int sig)
{
  static char unknown[64];

  switch (sig)
    {
    case 0: return "Signal 0";
#ifdef SIGHUP
    case SIGHUP: return "Hangup";
#endif
#ifdef SIGINT
    case SIGINT: return "Interrupt";
#endif
#ifdef SIGQUIT
    case SIGQUIT: return "Quit";
#endif
#ifdef SIGILL
    case SIGILL: return "Illegal instruction";
#endif
#ifdef SIGTRAP
    case SIGTRAP: return "Trace/breakpoint trap";
#endif
#ifdef SIGABRT
    case SIGABRT: return "Aborted";
#endif
#ifdef SIGFPE
    case SIGFPE: return "Floating point exception";
#endif
#ifdef SIGKILL
    case SIGKILL: return "Killed";
#endif
#ifdef SIGSEGV
    case SIGSEGV: return "Segmentation fault";
#endif
#ifdef SIGPIPE
    case SIGPIPE: return "Broken pipe";
#endif
#ifdef SIGALRM
    case SIGALRM: return "Alarm clock";
#endif
#ifdef SIGTERM
    case SIGTERM: return "Terminated";
#endif
#ifdef SIGUSR1
    case SIGUSR1: return "User defined signal 1";
#endif
#ifdef SIGUSR2
    case SIGUSR2: return "User defined signal 2";
#endif
    default:
      sprintf (unknown, "Unknown signal %d", sig);
      return unknown;
    }
}
