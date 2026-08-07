/* Console-build stubs for symbols owned by GUI modules.

   The terminal-only Windows build does not compile w32fns.c,
   w32image.c, w32select.c or the other GUI modules, but the core w32
   sources reference a number of their globals and simple helpers.
   Provide equivalent definitions here; the GUI build keeps using the
   originals.  The console input layer (w32inevt.c) is compiled for
   real keyboard support, and w32console.c supplies the terminal
   emulation itself.

Copyright (C) 2026 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.  */

#include <config.h>

#include <errno.h>
#include <io.h>		/* _setmode */
#include <stdarg.h>
#include <stdio.h>

#include "lisp.h"
#include "w32.h"
#include "w32common.h"
#include "w32term.h"
#include "fpending.h"

#include <windows.h>
#include <bcrypt.h>
#include <dbghelp.h>
#include <stdio.h>

/* Temporary startup diagnostic: print the stack on a stack overflow so
   the Windows loadup failure can be identified from the CI log.  */
static LONG WINAPI
stack_overflow_diag (EXCEPTION_POINTERS *ep)
{
  if (ep->ExceptionRecord->ExceptionCode == 0xC00000FD)
    {
      SymSetOptions (SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
      SymInitialize (GetCurrentProcess (), NULL, TRUE);
      void *addrs[40];
      USHORT n = RtlCaptureStackBackTrace (0, 40, addrs, NULL);
      fprintf (stderr, "DIAG: stack overflow, %u frames:\n", n);
      for (USHORT i = 0; i < n; i++)
	{
	  DWORD64 disp = 0;
	  char name[256] = "?";
	  union { char raw[sizeof (SYMBOL_INFO) + 256]; SYMBOL_INFO sym; } si;
	  memset (&si, 0, sizeof si);
	  si.sym.SizeOfStruct = sizeof (SYMBOL_INFO);
	  si.sym.MaxNameLen = 255;
	  if (SymFromAddr (GetCurrentProcess (), (DWORD64) addrs[i], &disp, &si.sym))
	    snprintf (name, sizeof name, "%s", si.sym.Name);
	  fprintf (stderr, "  %p %s+0x%llx\n", addrs[i], name, (unsigned long long) disp);
	}
      fflush (stderr);
      _resetstkoflw ();
    }
  return EXCEPTION_CONTINUE_SEARCH;
}

void
w32_install_stack_diag (void)
{
  SetUnhandledExceptionFilter (stack_overflow_diag);
}

/* w32image.c owns the GDI+ lifecycle in the GUI build.  */
void
w32_gdiplus_shutdown (void)
{
}

/* Cached system information, normally owned by w32fns.c.  */
SYSTEM_INFO sysinfo_cache;
OSVERSIONINFO osinfo_cache;
DWORD_PTR syspage_mask = 0;
int w32_major_version;
int w32_minor_version;
int w32_build_number;
int os_subtype = OS_SUBTYPE_NT;

/* The GUI build loads these dynamically; the console build has no
   window thread or debugger-dependent naming, so leave them NULL.  */
typedef BOOL (WINAPI *IsDebuggerPresent_Proc) (void);
typedef HRESULT (WINAPI *SetThreadDescription_Proc)
  (HANDLE hThread, PCWSTR lpThreadDescription);
IsDebuggerPresent_Proc is_debugger_present = NULL;
SetThreadDescription_Proc set_thread_description = NULL;

/* Input-thread identity and the interrupt event (w32term.c owns these
   in the GUI build).  init_crit is called by w32console.c's terminal
   init and by emacs.c in batch mode.  */
DWORD dwMainThreadId = 0;
CRITICAL_SECTION critsect;
HANDLE interrupt_handle = NULL;

void
init_crit (void)
{
  InitializeCriticalSection (&critsect);

  /* Manual-reset event: blocking system calls (sys_select etc.) wait
     on it so C-g can interrupt them.  */
  interrupt_handle = CreateEvent (NULL, TRUE, FALSE, NULL);
}

void
w32_init_main_thread (void)
{
  dwMainThreadId = GetCurrentThreadId ();
}

/* Cache information describing the NT system, as w32fns.c does.  */
void
cache_system_info (void)
{
  union
    {
      struct info
	{
	  char  major;
	  char  minor;
	  short platform;
	} info;
      DWORD data;
    } version;

  version.data = GetVersion ();
  w32_major_version = version.info.major;
  w32_minor_version = version.info.minor;

  if (version.info.platform & 0x8000)
    os_subtype = OS_SUBTYPE_9X;
  else
    os_subtype = OS_SUBTYPE_NT;

  GetSystemInfo (&sysinfo_cache);
  syspage_mask = (DWORD_PTR)sysinfo_cache.dwPageSize - 1;

  osinfo_cache.dwOSVersionInfoSize = sizeof (OSVERSIONINFO);
  GetVersionEx (&osinfo_cache);
  w32_build_number = osinfo_cache.dwBuildNumber;
}

char *
w32_version_string (void)
{
  /* NNN.NNN.NNNNNNNNNN */
  static char version_string[3 + 1 + 3 + 1 + 10 + 1];
  _snprintf (version_string, sizeof version_string, "%d.%d.%d",
	     w32_major_version, w32_minor_version, w32_build_number);
  return version_string;
}

char *
w32_strerror (int error_no)
{
  static char buf[500];
  DWORD ret;

  if (error_no == 0)
    error_no = GetLastError ();

  ret = FormatMessage (FORMAT_MESSAGE_FROM_SYSTEM |
		       FORMAT_MESSAGE_IGNORE_INSERTS,
		       NULL,
		       error_no,
		       0, /* choose most suitable language */
		       buf, sizeof (buf), NULL);

  while (ret > 0 && (buf[ret - 1] == '\n' ||
		     buf[ret - 1] == '\r' ))
      --ret;
  buf[ret] = '\0';
  if (!ret)
    sprintf (buf, "w32 error %d", error_no);

  return buf;
}

/* Registry-based resources and the GUI input hook are unavailable in
   the console build; the unicows loader is a no-op.  */
LPBYTE
w32_get_resource (const char *key, const char *name, LPDWORD type)
{
  return NULL;
}

void
load_unicows_dll_for_w32fns (HMODULE h)
{
}

void
setup_w32_kbdhook (HWND hwnd)
{
}

void
remove_w32_kbdhook (void)
{
}

void
w32_initialize_display_info (Lisp_Object display_name)
{
}

void
w32_sys_ring_bell (struct frame *f)
{
  Beep (800, 100);
}

/* Keyboard helpers normally owned by w32fns.c.  The console build has
   no low-level keyboard hook, so Win-key state falls back to the
   async key state and AltGr/caps handling is omitted; the keypad
   mapping and modifier conversion keep the same semantics.  */
int
check_w32_winkey_state (int vkey)
{
  return (GetAsyncKeyState (vkey) & 0x8000) != 0;
}

unsigned int
map_keypad_keys (unsigned int virt_key, unsigned int extended)
{
  if (virt_key < VK_CLEAR || virt_key > VK_DELETE)
    return virt_key;

  if (virt_key == VK_RETURN)
    return (extended ? VK_NUMPAD_ENTER : VK_RETURN);

  if (virt_key >= VK_PRIOR && virt_key <= VK_DOWN)
    return (!extended ? (VK_NUMPAD_PRIOR + (virt_key - VK_PRIOR)) : virt_key);

  if (virt_key == VK_INSERT || virt_key == VK_DELETE)
    return (!extended ? (VK_NUMPAD_INSERT + (virt_key - VK_INSERT)) : virt_key);

  if (virt_key == VK_CLEAR)
    return (!extended ? VK_NUMPAD_CLEAR : virt_key);

  return virt_key;
}

int
w32_kbd_mods_to_emacs (DWORD mods, WORD key)
{
  int retval = 0;

  if (mods & (RIGHT_ALT_PRESSED | LEFT_ALT_PRESSED))
    retval |= meta_modifier;
  if (mods & (RIGHT_CTRL_PRESSED | LEFT_CTRL_PRESSED))
    retval |= ctrl_modifier;
  if (mods & SHIFT_PRESSED)
    retval |= shift_modifier;
  return retval;
}

int
w32_kbd_patch_key (KEY_EVENT_RECORD *event, int cpId)
{
  unsigned int key_code = event->wVirtualKeyCode;
  unsigned int mods = event->dwControlKeyState;
  BYTE keystate[256];
  WORD chars[4];

  if (event->uChar.AsciiChar != 0)
    return 1;

  memset (keystate, 0, sizeof (keystate));
  keystate[key_code] = 0x80;
  if (mods & SHIFT_PRESSED)
    keystate[VK_SHIFT] = 0x80;
  if (mods & CAPSLOCK_ON)
    keystate[VK_CAPITAL] = 1;

  /* Translate the key with the current keyboard layout.  ToAscii
     reports dead-key sequences across calls; the composed character
     is delivered here for the second call's key event.  */
  if (ToAscii (key_code, event->wVirtualScanCode, keystate, chars, 0) > 0)
    event->uChar.AsciiChar = (char) chars[0];
  return 1;
}

/* The GUI build pumps its window-message queue from the input thread;
   the console build has no such queue.  */
int
drain_message_queue (void)
{
  return 0;
}

DWORD dwWindowsThreadId = 0;

/* Clipboard module (w32select.c) hooks; no clipboard in the console.  */
void
globals_of_w32select (void)
{
}

void
syms_of_w32select (void)
{
}

void
term_w32select (void)
{
}

/* getrandom over the Windows CSPRNG (fns.c secure-random).  */
ssize_t
getrandom (void *buffer, size_t length, unsigned int flags)
{
  if (BCryptGenRandom (NULL, buffer, length,
		       BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0)
    {
      errno = EIO;
      return -1;
    }
  return length;
}

/* binary-io / close-stream for mingw: lib/binary-io.c only serves
   DJGPP/EMX and gnulib-io is not linked on Windows.  */
int
set_binary_mode (int fd, int mode)
{
  return _setmode (fd, mode);
}

int
close_stream (FILE *stream)
{
  const bool some_pending = (__fpending (stream) != 0);
  const bool prev_fail = (ferror (stream) != 0);
  const bool fclose_fail = (fclose (stream) != 0);

  if (prev_fail || (fclose_fail && (some_pending || errno != EBADF)))
    {
      if (!prev_fail && !(fclose_fail && errno == 0))
	errno = fclose_fail ? errno : 0;
      return EOF;
    }
  return 0;
}
