#ifndef SYS_TIME_H_INCLUDED
#define SYS_TIME_H_INCLUDED

/* Under the MinGW ABI the CRT's <sys/time.h> exists (include_next yields
   it, providing struct timeval).  The MSVC CRT has no <sys/time.h>, and
   Emacs's w32 build deliberately avoids dragging in <winsock2.h> from here
   (ms-w32.h controls winsock inclusion), so for the MSVC ABI we define
   struct timeval locally with the standard Windows layout (two longs).
   This header is Emacs's own committed replacement under nt/inc/sys, so the
   MSVC branch here is the intended port surface.  */
#if defined _MSC_VER && !defined __MINGW32__
struct timeval
{
  long tv_sec;
  long tv_usec;
};
#else
# include_next <sys/time.h>
#endif

#define ITIMER_REAL      0
#define ITIMER_PROF      1

struct itimerval
{
  struct  timeval it_interval;	/* timer interval */
  struct  timeval it_value;	/* current value */
};

int getitimer (int, struct itimerval *);
int setitimer (int, struct itimerval *, struct itimerval *);

#endif /* SYS_TIME_H_INCLUDED */

/* end of sys/time.h */

