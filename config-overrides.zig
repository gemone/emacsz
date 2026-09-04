//! Per-target config.h override tables (single source of truth).
//! Shared by build.zig's addConfigHeader-based config generation (the
//! replacement for the former gen-config tool): each table applies
//! on top of the committed src/config_values.txt (Linux autoconf
//! results) for the named target tag.  The entries encode decisions
//! beyond mere library existence (e.g. macOS undefs HAVE_TIMER_SETTIME
//! to force the setitimer fallback even though the symbol exists).

const std = @import("std");

pub const Override = struct {
    name: []const u8,
    value: []const u8 = "",
};

// Linux TTY build: no window system / image / font backends are compiled
// (the zig build compiles only the 63 TTY core C sources), so the committed
// Linux autoconf snapshot's display knobs are undef'd -- parity with upstream
// `--without-x --without-ns` -- eliminating the declaration/compile drift.
// (musl/windows/macos overrides keep them undef'd too; this table makes the
// native Linux TTY build consistent with them.)
pub const linux_overrides = [_]Override{
    .{ .name = "HAVE_ANDROID" },
    .{ .name = "HAVE_GIF" },
    .{ .name = "HAVE_GTK3" },
    .{ .name = "HAVE_HAIKU" },
    .{ .name = "HAVE_HARFBUZZ" },
    .{ .name = "HAVE_IMAGEMAGICK" },
    .{ .name = "HAVE_IMAGEMAGICK7" },
    .{ .name = "HAVE_JPEG" },
    .{ .name = "HAVE_LIBOTF" },
    .{ .name = "HAVE_M17N_FLT" },
    .{ .name = "HAVE_NATIVE_IMAGE_API" },
    .{ .name = "HAVE_NS" },
    .{ .name = "HAVE_NTGUI" },
    .{ .name = "HAVE_PGTK" },
    .{ .name = "HAVE_PNG" },
    .{ .name = "HAVE_RSVG" },
    .{ .name = "HAVE_TIFF" },
    .{ .name = "HAVE_W32NOTIFY" },
    .{ .name = "HAVE_WEBP" },
    .{ .name = "HAVE_WINDOW_SYSTEM" },
    .{ .name = "HAVE_X11" },
    .{ .name = "HAVE_X11R6" },
    .{ .name = "HAVE_X11R6_XIM" },
    .{ .name = "HAVE_X11XTR6" },
    .{ .name = "HAVE_XAW3D" },
    .{ .name = "HAVE_XCB_SHAPE" },
    .{ .name = "HAVE_XCOMPOSITE" },
    .{ .name = "HAVE_XDBE" },
    .{ .name = "HAVE_XDESTROYSUBWINDOWS" },
    .{ .name = "HAVE_XDISPLAYCELLS" },
    .{ .name = "HAVE_XFIXES" },
    .{ .name = "HAVE_XFT" },
    .{ .name = "HAVE_XIM" },
    .{ .name = "HAVE_XINERAMA" },
    .{ .name = "HAVE_XINPUT2" },
    .{ .name = "HAVE_XKB" },
    .{ .name = "HAVE_XKBFREENAMES" },
    .{ .name = "HAVE_XKBREFRESHKEYBOARDMAPPING" },
    .{ .name = "HAVE_XPM" },
    .{ .name = "HAVE_XRANDR" },
    .{ .name = "HAVE_XRENDER" },
    .{ .name = "HAVE_XSHAPE" },
    .{ .name = "HAVE_XSYNC" },
    .{ .name = "HAVE_XSYNCTRIGGERFENCE" },
    .{ .name = "HAVE_XWIDGETS" },
    .{ .name = "HAVE_X_I18N" },
    .{ .name = "HAVE_X_SM" },
    .{ .name = "HAVE_X_WINDOWS" },
    .{ .name = "USE_CAIRO" },
    .{ .name = "USE_CAIRO_XCB" },
    .{ .name = "USE_GTK" },
    .{ .name = "USE_LUCID" },
    .{ .name = "USE_MOTIF" },
    .{ .name = "USE_XCB" },
    .{ .name = "USE_XIM" },
    .{ .name = "USE_X_TOOLKIT" },
    // Advertise only what the TTY build actually provides: drop XIM from
    // the runtime feature string (EMACS_CONFIG_FEATURES otherwise keeps
    // advertising the X Input Method although HAVE_XIM is now undef'd).
    .{ .name = "EMACS_CONFIG_FEATURES", .value = "\"ACL DBUS GMP GNUTLS GPM LCMS2 LIBXML2 NOTIFY INOTIFY PDUMPER SECCOMP SOUND SQLITE3 THREADS TREE_SITTER ZLIB\"" },
};

pub const musl_overrides = [_]Override{
    .{ .name = "HAVE_GNUTLS" },
    .{ .name = "HAVE_ALSA" },
    .{ .name = "HAVE_GPM" },
    .{ .name = "HAVE_DBUS" },
    // glibc-only features absent from musl; TERMINFO is dropped so
    // src/termcap.c (compiled via TERMCAP_OBJ) supplies the terminal
    // capabilities instead of ncurses; ACLs stay with the Zig package.
    .{ .name = "TERMINFO" },
    .{ .name = "TERMINFO_DEFINES_BC" },
    .{ .name = "USE_ACL" },
    .{ .name = "HAVE_ACL_GET_FILE" },
    .{ .name = "HAVE_EXECINFO_H" },
    .{ .name = "HAVE_GETADDRINFO_A" },
    .{ .name = "HAVE_MALLOC_TRIM" },
    .{ .name = "HAVE_RENAMEAT2" },
    .{ .name = "HAVE_LANGINFO__NL_PAPER_WIDTH" },
    .{ .name = "HAVE_SIGDESCR_NP" },
};
pub const windows_overrides = [_]Override{
    .{ .name = "HAVE_GNUTLS" },
    .{ .name = "HAVE_ALSA" },
    .{ .name = "HAVE_GPM" },
    .{ .name = "HAVE_DBUS" },
    .{ .name = "WINDOWSNT", .value = "1" },
    .{ .name = "DOS_NT", .value = "1" },
    // system-type drives every Lisp platform branch (files.el, dired,
    // ls-lisp, ...).  Without this the committed "gnu/linux" leaks into
    // the Windows image, so emacs believes it is on Linux and no
    // windows-nt code path runs -- e.g. ls-lisp then defaults to the
    // external `ls` (absent without msys2) and dired cannot list a dir.
    // (Console-only builds also need term/w32-nt.el to default the w32
    // GUI/image version vars that w32fns.c et al. define only under
    // HAVE_NTGUI.)
    .{ .name = "SYSTEM_TYPE", .value = "\"windows-nt\"" },
    // The committed Linux config_values.txt advertises Linux-only subsystems
    // (DBUS, GPM, INOTIFY, SECCOMP, SOUND, XIM) in EMACS_CONFIG_FEATURES, but
    // the Windows console build provides none of them, and it also undefs
    // HAVE_GNUTLS (the vendored GnuTLS is macOS-only; Windows does not link
    // it).  Advertise only what the Windows build actually provides, all in
    // one clean CR-free string: ACL (USE_ACL via the Zig gnulib-acl package),
    // GMP, LCMS2, LIBXML2, NOTIFY, PDUMPER, SQLITE3, THREADS, TREE_SITTER,
    // ZLIB.  This deliberately omits GNUTLS (undef'd above) and replaces the
    // raw value so the -Dwith-*=false feature-token rewrite (which
    // strips/requotes this value) cannot corrupt config.h.
    .{ .name = "EMACS_CONFIG_FEATURES", .value = "\"ACL GMP LCMS2 LIBXML2 NOTIFY PDUMPER SQLITE3 THREADS TREE_SITTER ZLIB\"" },
    .{ .name = "HAVE_BCRYPT_H", .value = "1" },
    .{ .name = "HAVE_LIB_BCRYPT", .value = "1" },
    .{ .name = "USE_UNLOCKED_IO" },
    // HAVE_STACK_OVERFLOW_HANDLING: undef for the console build (its
    // keyboard.c consumer would call w32_reset_stack_overflow_guard from
    // w32fns.c, a -Dgui module); build.zig's -Dgui defines re-enable it
    // together with the GUI modules.  The Linux snapshot has it =1, so the
    // undef must be explicit here.
    .{ .name = "HAVE_STACK_OVERFLOW_HANDLING" },
    .{ .name = "HAVE_TIMERFD" },
    // _setjmp/_longjmp: plain register-restore non-local exit (no SEH
    // unwind walk).  The MSVC CRT's full longjmp calls RtlUnwindEx, which
    // walks JIT/AOT frames; with the plain variant the handler resumption
    // is a direct rsp/rip restore, so handler-carrying units compile and
    // the JIT condition-case path works identically to MinGW.
    .{ .name = "HAVE__SETJMP", .value = "1" },
    .{ .name = "HAVE_SIGSETJMP" },
    .{ .name = "HAVE_MMAP" },
    .{ .name = "HAVE_MEMMEM" },
    .{ .name = "HAVE_ACCEPT4" },
    .{ .name = "HAVE_ALIGNED_ALLOC" },
    .{ .name = "HAVE_MALLOC_TRIM" },
    .{ .name = "HAVE_GET_CURRENT_DIR_NAME" },
    .{ .name = "HAVE_GETADDRINFO_A" },
    .{ .name = "HAVE_GETIFADDRS" },
    .{ .name = "HAVE_GETRUSAGE" },
    .{ .name = "HAVE_NET_IF_H" },
    .{ .name = "HAVE_IFADDRS_H" },
    .{ .name = "HAVE_SYS_PERSONALITY_H" },
    .{ .name = "HAVE_PERSONALITY_ADDR_NO_RANDOMIZE" },
    .{ .name = "HAVE_SYNC" },
    .{ .name = "HAVE_STRSIGNAL" },
    .{ .name = "HAVE_LINUX_SYSINFO" },
    .{ .name = "HAVE_SYS_UTSNAME_H" },
    .{ .name = "HAVE_LINUX_FS_H" },
    .{ .name = "HAVE_SYS_UN_H" },
    .{ .name = "HAVE_STRUCT_UNIPAIR_UNICODE" },
    .{ .name = "HAVE_POSIX_SPAWN" },
    .{ .name = "HAVE_POSIX_SPAWN_FILE_ACTIONS_ADDCHDIR_NP" },
    .{ .name = "HAVE_DECL_POSIX_SPAWN_SETSID" },
    .{ .name = "HAVE_TM_GMTOFF" },
    .{ .name = "HAVE_GRANTPT" },
    .{ .name = "HAVE_POSIX_OPENPT" },
    .{ .name = "HAVE_PTYS" },
    .{ .name = "GNU_LINUX" },
    .{ .name = "UNIX98_PTYS" },
    .{ .name = "HAVE_PTY_H" },
    .{ .name = "HAVE_STDIO_EXT_H" },
    .{ .name = "HAVE_DECL___FPENDING" },
    .{ .name = "USABLE_SIGIO" },
    .{ .name = "SIGNALS_VIA_CHARACTERS" },
    .{ .name = "HAVE_GETPWENT" },
    .{ .name = "HAVE_ENDPWENT" },
    .{ .name = "HAVE_GETGRENT" },
    .{ .name = "HAVE_ENDGRENT" },
    .{ .name = "HAVE_PROCFS" },
    .{ .name = "HAVE_INOTIFY" },
    .{ .name = "HAVE_PTHREAD" },
    .{ .name = "HAVE_PTHREAD_H" },
    .{ .name = "HAVE_PTHREAD_SETNAME_NP" },
    .{ .name = "HAVE_PTHREAD_SETNAME_NP_1ARG" },
    .{ .name = "HAVE_PTHREAD_SETNAME_NP_3ARG" },
    .{ .name = "HAVE_PTHREAD_SET_NAME_NP" },
    .{ .name = "HAVE_PTHREAD_SIGMASK" },
    .{ .name = "HAVE_STRUCT_DIRENT_D_TYPE" },
    .{ .name = "HAVE_LINUX_SECCOMP_H" },
    .{ .name = "HAVE_LINUX_FILTER_H" },
    .{ .name = "HAVE_DECL_SECCOMP_SET_MODE_FILTER" },
    .{ .name = "HAVE_DECL_SECCOMP_FILTER_FLAG_TSYNC" },
    .{ .name = "HAVE_STRUCT_TM_TM_ZONE" },
    .{ .name = "HAVE_STRUCT_TM_TM_GMTOFF" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIM_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIMESPEC_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIMENSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIM_ST__TIM_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_BIRTHTIMESPEC_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_BIRTHTIM_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_BIRTHTIMENSEC" },
    .{ .name = "TYPEOF_STRUCT_STAT_ST_ATIM_IS_STRUCT_TIMESPEC" },
    .{ .name = "HAVE_DECL_GETC_UNLOCKED" },
    .{ .name = "HAVE_DECL_GETDELIM" },
    .{ .name = "HAVE_DECL_GETLINE" },
    .{ .name = "HAVE_DECL_CLEARERR_UNLOCKED" },
    .{ .name = "HAVE_DECL_FEOF_UNLOCKED" },
    .{ .name = "HAVE_DECL_FERROR_UNLOCKED" },
    .{ .name = "HAVE_DECL_FFLUSH_UNLOCKED" },
    .{ .name = "HAVE_DECL_FGETS_UNLOCKED" },
    .{ .name = "HAVE_DECL_FILENO_UNLOCKED" },
    .{ .name = "HAVE_DECL_FPUTC_UNLOCKED" },
    .{ .name = "HAVE_DECL_FPUTS_UNLOCKED" },
    .{ .name = "HAVE_DECL_FREAD_UNLOCKED" },
    .{ .name = "HAVE_DECL_FWRITE_UNLOCKED" },
    .{ .name = "HAVE_DECL_GETCHAR_UNLOCKED" },
    .{ .name = "HAVE_DECL_PUTCHAR_UNLOCKED" },
    .{ .name = "HAVE_DECL_PUTC_UNLOCKED" },
    .{ .name = "HAVE_STDBIT_H" },
    .{ .name = "HAVE_SYS_RANDOM_H" },
    .{ .name = "HAVE_EXECINFO_H" },
    // Windows native separator conventions: backslash directory
    // separator and ':' device separator.  The committed Linux values
    // ('/' and 0) made Fexpand_file_name miss every drive letter and
    // abort on any absolute path.
    .{ .name = "DIRECTORY_SEP", .value = "'\\\\'" },
    // Windows path-list separator is ';' (the Linux ':' would split
    // every drive letter off "D:/..." paths during startup).
    .{ .name = "SEPCHAR", .value = "';'" },
    // Windows has no /dev/null; its null device is NUL.  The committed
    // Linux value ("/dev/null") made every subprocess's null stdin/stdout
    // (call-process, make-process, ...) fail to open with "No such file or
    // directory" during compile-lisp on the Windows CI runner (woman.el
    // etc.), aborting the whole build.
    .{ .name = "NULL_DEVICE", .value = "\"NUL\"" },
    // Module suffix mirrors upstream configure.ac's mingw case
    // (MODULES_SUFFIX follows DYNAMIC_LIB_SUFFIX = ".dll"). See
    // configure.ac:5093-5116.
    .{ .name = "MODULES_SUFFIX", .value = "\".dll\"" },
};
pub const macos_overrides = [_]Override{
    .{ .name = "HAVE_DECL_GETC_UNLOCKED" },
    .{ .name = "HAVE_DECL_CLEARERR_UNLOCKED" },
    .{ .name = "HAVE_DECL_FEOF_UNLOCKED" },
    .{ .name = "HAVE_DECL_FERROR_UNLOCKED" },
    .{ .name = "HAVE_DECL_FFLUSH_UNLOCKED" },
    .{ .name = "HAVE_DECL_FGETS_UNLOCKED" },
    .{ .name = "HAVE_DECL_FILENO_UNLOCKED" },
    .{ .name = "HAVE_DECL_FPUTC_UNLOCKED" },
    .{ .name = "HAVE_DECL_FPUTS_UNLOCKED" },
    .{ .name = "HAVE_DECL_FREAD_UNLOCKED" },
    .{ .name = "HAVE_DECL_FWRITE_UNLOCKED" },
    .{ .name = "HAVE_DECL_GETCHAR_UNLOCKED" },
    .{ .name = "HAVE_DECL_PUTCHAR_UNLOCKED" },
    .{ .name = "HAVE_DECL_PUTC_UNLOCKED" },
    // Darwin struct stat uses st_atimespec/st_mtimespec/st_ctimespec
    // instead of glibc's st_atim/st_mtim/st_ctim, so flip the knob the
    // committed stat-time.h switches on.
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIM_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIMESPEC_TV_NSEC", .value = "1" },
    // DARWIN_OS selects the Mach-O subr section (__DATA,subrs) and the
    // darwin-specific code paths; the committed Linux values enable
    // Linux-only subsystems (GPM console mouse, the copy_file_range
    // wrapper) and glibc's <malloc.h>; tree-sitter is vendored and
    // enabled on every platform.
    .{ .name = "DARWIN_OS", .value = "1" },
    // kqueue is the macOS file-notification backend (src/kqueue.c is
    // compiled for macOS); without the feature, filenotify reports "No
    // file notification package available" and eglot's dynamic
    // didChangeWatchedFiles registration fails.
    .{ .name = "HAVE_KQUEUE", .value = "1" },
    .{ .name = "HAVE_GPM" },
    .{ .name = "HAVE_COPY_FILE_RANGE" },
    .{ .name = "HAVE_MALLOC_H" },
    .{ .name = "HAVE_TIMERFD" },
    .{ .name = "HAVE_STDIO_EXT_H" },
    .{ .name = "HAVE_SYS_SYSINFO_H" },
    .{ .name = "HAVE_LINUX_SECCOMP_H" },
    .{ .name = "HAVE_LINUX_FS_H" },
    // The committed Linux answer defines GNU_LINUX; without an undef it
    // leaks into darwin builds and sysdep.c selects the /proc-based
    // system_process_attributes, making process-attributes return nil
    // (no /proc on macOS), which breaks desktop-tests.
    .{ .name = "GNU_LINUX" },
    .{ .name = "HAVE_MEMPCPY" },
    .{ .name = "HAVE_MEMRCHR" },
    .{ .name = "HAVE_LANGINFO__NL_PAPER_WIDTH" },
    .{ .name = "HAVE_ENVIRON_DECL" },
    // POSIX timers (timer_create/timer_settime/timer_getoverrun) are
    // glibc-only; without HAVE_TIMER_SETTIME, syssignal.h leaves
    // HAVE_ITIMERSPEC undefined and atimer.c/profiler.c fall back to
    // setitimer, which Darwin does provide.
    .{ .name = "HAVE_TIMER_SETTIME" },
    .{ .name = "HAVE_TIMER_GETOVERRUN" },
    // pty.h is a glibc header; the Darwin PTY path uses the baked
    // PTY_OPEN (posix_openpt) macro instead of including it.
    .{ .name = "HAVE_PTY_H" },
    // The SDK has no OSS sound headers and no sound architecture.
    .{ .name = "HAVE_SYS_SOUNDCARD_H" },
    .{ .name = "HAVE_MACHINE_SOUNDCARD_H" },
    .{ .name = "HAVE_SOUNDCARD_H" },
    .{ .name = "HAVE_SOUND" },
    // sys/personality.h is Linux-only; the ASLR personality() call is
    // not available on Darwin.
    .{ .name = "HAVE_PERSONALITY_ADDR_NO_RANDOMIZE" },
    // linux/kd.h backs HAVE_STRUCT_UNIPAIR_UNICODE on Linux only.
    .{ .name = "HAVE_STRUCT_UNIPAIR_UNICODE" },
    // Darwin declares strmode in <string.h> (BSD heritage); flip the
    // knob so filemode.h stops declaring its own copy.
    .{ .name = "HAVE_DECL_STRMODE", .value = "1" },
    // Darwin's pthread_setname_np takes a single argument.
    .{ .name = "HAVE_PTHREAD_SETNAME_NP_1ARG", .value = "1" },
    .{ .name = "HAVE_PTHREAD_SETNAME_NP_3ARG" },
    // Linux-kernel/glibc-only APIs absent from the Darwin SDK.
    .{ .name = "HAVE_ALSA" },
    .{ .name = "HAVE_DBUS" },
    .{ .name = "HAVE_DBUS_MESSAGE_SET_ALLOW_INTERACTIVE_AUTHORIZATION" },
    .{ .name = "HAVE_DBUS_TYPE_IS_VALID" },
    .{ .name = "HAVE_DBUS_VALIDATE_BUS_NAME" },
    .{ .name = "HAVE_DBUS_VALIDATE_INTERFACE" },
    .{ .name = "HAVE_DBUS_VALIDATE_MEMBER" },
    .{ .name = "HAVE_DBUS_VALIDATE_PATH" },
    .{ .name = "HAVE_DBUS_WATCH_GET_UNIX_FD" },
    .{ .name = "HAVE_INOTIFY" },
    .{ .name = "HAVE_INOTIFY_INIT" },
    .{ .name = "HAVE_INOTIFY_INIT1" },
    .{ .name = "HAVE_LINUX_FILTER_H" },
    .{ .name = "HAVE_LINUX_SYSINFO" },
    .{ .name = "HAVE_DECL_SECCOMP_SET_MODE_FILTER" },
    .{ .name = "HAVE_DECL_SECCOMP_FILTER_FLAG_TSYNC" },
    // The committed Linux value advertises Linux-only subsystems
    // (SECCOMP, DBUS, GPM, INOTIFY, SOUND, XIM) in
    // EMACS_CONFIG_FEATURES; the seccomp ert tests key off that token,
    // so a darwin build must not claim them.
    .{ .name = "EMACS_CONFIG_FEATURES", .value = "\"ACL GMP GNUTLS LCMS2 LIBXML2 NOTIFY PDUMPER SQLITE3 THREADS TREE_SITTER ZLIB\"" },
    .{ .name = "HAVE_LINUX_XATTR_H" },
    .{ .name = "HAVE_MNTENT_H" },
    .{ .name = "HAVE_SETMNTENT" },
    .{ .name = "HAVE_PROCFS" },
    .{ .name = "HAVE_MALLOC_TRIM" },
    .{ .name = "HAVE_RENAMEAT2" },
    .{ .name = "HAVE_GETRANDOM" },
    .{ .name = "HAVE_PIPE2" },
    .{ .name = "HAVE_ACCEPT4" },
    .{ .name = "HAVE_SCHED_GETAFFINITY" },
    .{ .name = "HAVE_SCHED_GETAFFINITY_LIKE_GLIBC" },
    .{ .name = "HAVE_GET_CURRENT_DIR_NAME" },
    .{ .name = "HAVE_SIGDESCR_NP" },
    .{ .name = "HAVE_GETADDRINFO_A" },
    .{ .name = "HAVE_GETPT" },
    .{ .name = "HAVE_DECL_SYSINFO" },
    // Darwin's struct ifreq exposes ifr_addr/ifr_broadaddr but not the
    // Linux-only ifr_netmask member; process.c then falls back to
    // reading the address union directly.
    .{ .name = "HAVE_STRUCT_IFREQ_IFR_NETMASK" },
    // The committed Linux answer data must not leak into a darwin build:
    // system-type drives the Lisp platform branches (files.el, startup.el,
    // dired, ...), and the module suffixes follow upstream configure.ac's
    // darwin case.  EMACS_CONFIGURATION is set separately from the argv
    // triple (below) so the arch matches the actual build target.
    .{ .name = "SYSTEM_TYPE", .value = "\"darwin\"" },
    .{ .name = "DYNAMIC_LIB_SUFFIX", .value = "\".dylib\"" },
    .{ .name = "DYNAMIC_LIB_SECONDARY_SUFFIX", .value = "\".so\"" },
    // Module suffixes mirror upstream configure.ac (MODULES_SUFFIX follows
    // DYNAMIC_LIB_SUFFIX; darwin additionally sets MODULES_SECONDARY_SUFFIX =
    // DYNAMIC_LIB_SECONDARY_SUFFIX = ".so" so dlopen-based modules load on
    // macOS alongside the .dylib form). See configure.ac:5093-5116.
    .{ .name = "MODULES_SUFFIX", .value = "\".dylib\"" },
    .{ .name = "MODULES_SECONDARY_SUFFIX", .value = "\".so\"" },
};
