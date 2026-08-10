//! Native Zig provider of the `dynlib_*` dynamic-loading ABI that
//! src/dynlib.c otherwise implements (its POSIX / HAVE_UNISTD_H branch).
//! Track-B B-Z (HAVE_MODULES_ZIG): the independent Zig dynamic-module
//! LOADER, the native-linking parallel to B-C (the upstream HAVE_MODULES
//! subsystem, which compiles src/dynlib.c).
//!
//! This is the α slice (plan §13.5 Option α): the package exports the
//! exact 7 names declared in src/dynlib.h as C-ABI `export fn`, backing
//! them with the platform libc dlopen/dlsym/dlclose/dlerror/dladdr. It
//! is NOT a from-scratch raw-syscall ELF loader (that is Option γ, a
//! multi-cycle project: PT_LOAD mmap, the full R_X86_64_*/R_AARCH64_*
//! relocation families, DT_NEEDED recursive loading against the main
//! link-map, TLS DTV allocation, DT_INIT_ARRAY constructors). The
//! honest caveat is that α still routes the load through ld.so (libc
//! dlopen), so the load path is not yet libc-free and the static-musl
//! dlopen dead-end is not yet solved -- that is γ's payoff. What α
//! delivers is build/load ownership + ABI-level decoupling: when
//! -Dmodules-zig is on, src/dynlib.c is dropped from the compile and
//! this package satisfies the identical dynlib_* ABI at link time, so
//! the module runtime (emacs-module.c), treesit grammar loading
//! (treesit.c) and the .zeln loader (compz.c) all resolve dynlib_*
//! through here. γ later replaces the dlopen extern calls below WITHOUT
//! touching C again -- the `export fn` surface is the seam.
//!
//! Flag parity with src/dynlib.c is load-bearing:
//!   - dynlib_open        uses RTLD_LAZY|RTLD_GLOBAL  (dynlib.c:279).
//!     GLOBAL (not LOCAL) is what lets a module's symbols enter the
//!     global namespace and resolve against the main binary / each
//!     other. std.DynLib.open defaults to RTLD_LOCAL, so this package
//!     declares the extern directly instead of using it.
//!   - dynlib_open_for_eln uses RTLD_LAZY (no GLOBAL) (dynlib.c:286,
//!     the HAVE_NATIVE_COMP branch). Needed when -Dnative-comp-zig is
//!     co-on and compz.c loads a .zeln.
//!   - dynlib_error       calls dlerror exactly once (one-shot,
//!     consumed-on-read, thread-local; calling it twice loses the first
//!     message -- dynlib.c:313). emacs-module.c:1222 builds the
//!     module-open-failed error string from this return immediately.
//!   - dynlib_addr        mirrors dynlib.c:297-310: NULLs both outparams,
//!     fills them from a Dl_info only when dladdr succeeds AND both
//!     dli_fname and dli_sname are present.
//!
//! Built as a static lib (b.addLibrary + linkLibrary, like the gnulib-*
//! packages) and linked into temacs's root module. ReleaseFast (leaf
//! libc-call wrappers) so it pulls in no Zig runtime/panic handler the
//! C executable would have to satisfy. POSIX-only this cycle
//! (glibc-Linux + macOS); the WINDOWSNT branch of dynlib.c (LoadLibrary
//! / GetProcAddress / GetModuleHandleEx) is not ported -- the build
//! forces -Dmodules-zig OFF on Windows and static musl.

const std = @import("std");
const builtin = @import("builtin");

// dlfcn.h flag values. Identical on glibc-Linux and macOS (RTLD_LAZY=1,
// RTLD_GLOBAL=0x100); the package is POSIX-only this cycle, so the
// switch @compileErrors loudly for anything else rather than guessing.
const RTLD_LAZY: c_int = 1;
const RTLD_GLOBAL: c_int = switch (builtin.os.tag) {
    .linux, .macos, .ios, .watchos, .tvos => 0x100,
    else => @compileError(
        "emacs-dynlib: RTLD_GLOBAL is unknown for this OS; the package is " ++
            "POSIX (libc dlopen) only this cycle (glibc-Linux + macOS)",
    ),
};

// Dl_info layout for dladdr(3). The four-field order (fname, fbase,
// sname, saddr) is the same on glibc and libSystem; declared extern so
// the C-ABI layout matches the libc struct the call fills in.
const Dl_info = extern struct {
    dli_fname: ?[*:0]const u8,
    dli_fbase: ?*anyopaque,
    dli_sname: ?[*:0]const u8,
    dli_saddr: ?*anyopaque,
};

// The libc dynamic-loading surface this package wraps. Resolved against
// libc at the final temacs link (dlopen et al. live in libc on glibc
// 2.34+ and libSystem on macOS; no -ldl is needed).
extern "c" fn dlopen(file: [*:0]const u8, mode: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
extern "c" fn dlclose(handle: ?*anyopaque) c_int;
extern "c" fn dlerror() ?[*:0]u8;
extern "c" fn dladdr(addr: ?*anyopaque, info: *Dl_info) c_int;

// dynlib_handle_ptr is `void *` in src/dynlib.h; carried as ?*anyopaque.
// dynlib_function_ptr is `void (*)(void)` (ATTRIBUTE_MAY_ALIAS); a
// function pointer is returned in the same word-sized register as a
// data pointer on every ABI this package targets, so dynlib_func below
// returns ?*anyopaque and the C caller casts (exactly as dynlib.c:339
// casts the dlfunc result).

/// dynlib_open: load the shared object at PATH and return its handle, or
/// NULL on failure (the error is then available from dynlib_error).
/// RTLD_LAZY|RTLD_GLOBAL matches src/dynlib.c:279 so module symbols
/// resolve against the global namespace (the main binary and other
/// modules), which is what emacs-module.c's init contract assumes.
export fn dynlib_open(path: [*:0]const u8) ?*anyopaque {
    return dlopen(path, RTLD_LAZY | RTLD_GLOBAL);
}

/// dynlib_open_for_eln: load a native-compiled artifact (.eln/.zeln).
/// RTLD_LAZY with NO RTLD_GLOBAL matches src/dynlib.c:286 (the
/// HAVE_NATIVE_COMP branch): eln/zeln objects are self-contained and
/// must NOT inject their symbols into the global namespace. Compiled
/// always (superset of dynlib.c's HAVE_NATIVE_COMP gate) so every
/// switch combination resolves.
export fn dynlib_open_for_eln(path: [*:0]const u8) ?*anyopaque {
    return dlopen(path, RTLD_LAZY);
}

/// dynlib_sym: resolve SYM in the shared object behind HANDLE, or NULL
/// on failure (the error, if any, from dynlib_error). Backs
/// emacs-module.c:1224 (plugin_is_GPL_compatible), treesit.c:911
/// (tree_sitter_* language fn) and compz.c:770 (zeln_entry).
export fn dynlib_sym(handle: ?*anyopaque, sym: [*:0]const u8) ?*anyopaque {
    return dlsym(handle, sym);
}

/// dynlib_func: function-pointer variant of dynlib_sym. src/dynlib.c:332-340
/// defines `dlfunc` as the real dlfunc(3) when HAVE_DLFUNC, else aliases it
/// to dynlib_sym; both reduce to a dlsym whose result is cast to
/// `void (*)(void)`. emacs-module.c:1228 uses this for emacs_module_init.
export fn dynlib_func(handle: ?*anyopaque, sym: [*:0]const u8) ?*anyopaque {
    return dlsym(handle, sym);
}

/// dynlib_close: decrement HANDLE's refcount, unloading it when it
/// reaches zero. Returns 1 on success, 0 on failure -- matching
/// src/dynlib.c:322 (`return dlclose (h) == 0;`). Only comp.c (gccjit
/// native-comp) calls this on the live paths; the module path keeps
/// modules resident for the Emacs lifetime, so this is rarely hit.
export fn dynlib_close(handle: ?*anyopaque) c_int {
    return @intFromBool(dlclose(handle) == 0);
}

/// dynlib_error: return a human-readable description of the last dynlib
/// failure, or NULL if none is pending. dlerror(3) is CONSUMED-ON-READ
/// and thread-local: calling it twice loses the first message, so this
/// invokes it exactly once (mirroring src/dynlib.c:313 -- which likewise
/// returns dlerror() directly with no copy). Callers (emacs-module.c:1222,
/// treesit.c:879/913) consume the string immediately on the calling
/// thread, so the libc-owned pointer is valid for the duration of use.
export fn dynlib_error() ?[*:0]const u8 {
    return dlerror();
}

/// dynlib_addr: best-effort attribution of FUNCPTR to the file
/// (*FILE_OUT) and symbol (*SYM_OUT) it belongs to. Both outparams are
/// NULLed first; they are set only when dladdr succeeds AND both
/// dli_fname and dli_sname are present (src/dynlib.c:297-310). Backs
/// print.c:2016 (Lisp backtrace annotation) and treesit.c:941 (records
/// the language-function file for error reporting).
export fn dynlib_addr(
    funcptr: ?*anyopaque,
    file_out: *?[*:0]const u8,
    sym_out: *?[*:0]const u8,
) void {
    file_out.* = null;
    sym_out.* = null;
    var info: Dl_info = std.mem.zeroes(Dl_info);
    if (dladdr(funcptr, &info) != 0 and
        info.dli_fname != null and info.dli_sname != null)
    {
        file_out.* = info.dli_fname;
        sym_out.* = info.dli_sname;
    }
}
