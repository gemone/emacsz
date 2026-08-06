# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Emacs Zig Migration

This repository contains GNU Emacs with an ongoing effort to modernize the build system and codebase by migrating from Autotools + Gnulib to Zig.

### Current Status
- **Goal 1 — Build entirely with `zig build`, no `automake`/`make`: ✅ Done.**
  `zig build` is self-sufficient: it runs `./configure` as a build step
  (generating `src/config.h` via real autoconf feature probes), then
  compiles and links `temacs`. No manual `./configure`/`make` step is
  needed, locally or in CI.
- **Goal 2 — Zig controls linking, decouple from libc: 🚧 In progress.**
  Zig drives all compile/link. Runtime gnulib functions are progressively
  provided by independent Zig packages: `tools/gnulib-str` (`memeq`/`streq`),
  `tools/gnulib-ctype` (`c_isalpha` & co), `tools/gnulib-stdbit` (the C23
  bit-count helpers), `tools/gnulib-hash` (SHA1, SHA-224/256/384/512,
  SHA3-224/256/384/512 and MD5, backing `secure-hash`),
  `tools/gnulib-sig2str` (`sig2str`/`str2sig`,
  backing `signal-names`), `tools/gnulib-filemode` (`strmode`/
  `filemodestring`, backing `file-attributes` string modes),
  `tools/gnulib-timespec` (`dtotimespec`/`timespec_add`/`timespec_sub`,
  plus the make_timespec/timespec_cmp extern-inlines, backing sit-for
  timeouts and gc timing), `tools/gnulib-c-strcase` (`c_strcasecmp`/
  `c_strncasecmp`), `tools/gnulib-filevercmp`
  (`filevercmp`/`filenvercmp`, backing `string-version-lessp`),
  `tools/gnulib-sigdescr-np` (`sigdescr_np`, backing safe_strsignal),
  `tools/gnulib-nproc` (`num_processors`, backing `num-processors`, via
  raw syscalls + sysfs/proc reads), `tools/gnulib-tempname`
  (`gen_tempname`/`mkostemp`, backing `make-temp-file` and filelock, via
  getrandom + raw openat/mkdir/lstat), and `tools/emacs-time` +
  `tools/emacs-nanosleep` (realtime clock / nanosleep with no libc call),
  `tools/gnulib-fsusage` (`get_fs_usage`, backing `file-system-info`, via
  raw statfs), and `tools/gnulib-getloadavg` (`getloadavg`, backing
  `load-average`, via raw sysinfo), and `tools/gnulib-careadlinkat`
  (`careadlinkat`, backing `file-symlink-p`/`file-truename`), and
  `tools/gnulib-dtoastr` (`dtoastr`, accurate float printing), and
  `tools/gnulib-stat-time` (`get_stat_*`, backing `file-attributes` time
  elements), and `tools/gnulib-boot-time` (`get_boot_time`, backing
  lock-file identification). The remaining lib/*.c files in the build
  are either empty on glibc or unexercised by Emacs. Deeper libc
  decoupling (file-I/O, time modules) is ongoing.
- **Goal 3 — Runnable on Linux: ✅ Done.** The final image is
  byte-compiled: `zig build dump` (source bootstrap) →
  `zig build compile-lisp` → `zig build dump-compiled`; `zig build check`
  runs 582 built-in `ert` tests across 40 suites (all passing), and
  `zig build check-all` runs all 484 upstream-discovered suites and
  classifies every outcome (PASS/FAIL/HANG/CRASH/LOAD). The full sweep
  passes all but one timing-dependent live-server test (eglot's
  `eglot-test-basic-stream-diagnostics`, needs a running ty/ruff server);
  the two suites that exceed the default 90s timeout (tramp-tests,
  package-vc-tests) pass with `CHECK_ALL_TIMEOUT=600`.

Zig version: **0.16.0** (strict).

## Development Commands

### Primary Build Workflow
```bash
zig build              # Build temacs + emacs wrapper (self-sufficient)
zig build dump         # Source (bootstrap) dump
zig build compile-lisp # Byte-compile lisp/ (incremental)
zig build dump-compiled # Final dump with compiled lisp
zig build smoke        # Verify the dumped emacs starts + evals Lisp
zig build check        # Run 582 built-in ert tests (alias: zig build test)
zig build check-all    # Run all 484 suites; classify PASS/FAIL/HANG/CRASH/LOAD
zig build help         # Show available steps + current status
```

Generated data (gitignored, required by dump/check): run
`generate-charsets`, `generate-unidata`, `generate-charprop`,
`generate-cedet-grammars` once, and `generate-loaddefs` after every
`dump`/`dump-compiled` (check steps regenerate loaddefs themselves).

`zig build` is the single entry point — there is **no `make` and no
manual `./configure` step**. The first `zig build` in a fresh checkout
runs `./configure` (slow, one-time) to produce `src/config.h`; later
builds skip it (guarded on `src/config.h` existence).

### Bootstrap data for `dump`/`check`
`zig build dump` and `zig build check` need generated charset + unicode
data (gitignored). Generate once:
```bash
zig build generate-charsets   # etc/charsets/*.map + cp51932/eucjp-ms.el
zig build generate-unidata    # lisp/international/{charscript,emoji-zwj}.el
```

### Testing
```bash
zig build check                            # 582 ert tests across 40 suites
file zig-out/bin/temacs                    # Verify the produced binary
```

### CI/CD
GitHub Actions workflow `.github/workflows/build-zig-native.yml` is a
pure `zig build` flow end-to-end (no `make`, no separate configure step).

## Architecture Overview

### Directory Structure
- **`src/`** - Core Emacs C code (630+ files, ~500K lines)
  - `emacs.c` - Main entry point
  - `lisp.h` - Lisp object system and interpreter interface
  - `alloc.c` - Memory management and garbage collector
  - `xdisp.c` (~39K lines) - Display engine
  - `keyboard.c` - Input handling
  - `buffer.c`, `window.c`, `frame.c` - Buffer/window management
  - `process.c` - Subprocess handling

- **`lib/`** - Gnulib implementations (330+ files providing POSIX compatibility)
  - Functions like `getline()`, `mktime()`, `nanosleep()`
  - Header wrappers for portability
  - Primary target for Zig stdlib migration

- **`lisp/`** - Emacs Lisp code (most editor functionality)
- **`nextstep/`** - macOS/Cocoa app templates
  - `Emacs.base/` - Standard Emacs.app template
  - `EmacsZ.base/` - Zig-built app template (distinguishes Zig builds)
- **`m4/`** - Autoconf macros (149 files)
- **`configure.ac`** - Autoconf configuration (427KB, heavily modified for Zig)
- **`build-aux/`** - Build utilities

### Platform-Specific Code
- **`android/`** - Android port
- **`nt/`** - Windows NT port
- **`x/`** - X11 window system integration
- **`lwlib/`** - Lucid widget library

### Emacs Core Architecture
1. **Lisp Interpreter** - Bytecode interpreter for Emacs Lisp
2. **Display Engine** - Redisplay logic (xdisp.c)
3. **Input System** - Keyboard/mouse handling
4. **Memory Management** - Garbage-collected Lisp objects (alloc.c)
5. **Buffer System** - Text editing primitives
6. **Window System** - Multi-window management

## Zig Integration Points

### Current Zig Configuration (configure.ac:1581-1854)
```autoconf
# Compiler detection and replacement
AC_CHECK_PROGS([ZIG_CC], [zig])
if test -n "$ZIG_CC"; then
  CC="$ZIG_CC cc"
  AR="$ZIG_CC ar"
  RANLIB="$ZIG_CC ranlib"
fi

# Target triple configuration for macOS
case $host_os in
  darwin*)
    ZIG_TARGET="aarch64-macos-none"  # or x86_64-macos-none
    ;;
esac

# Filter incompatible flags
# Removes: -Werror=implicit-function-declaration, -Wimplicit, etc.
```

### Zig Target Triples Used
- macOS ARM64: `aarch64-macos-none`
- macOS Intel: `x86_64-macos-none`
- Linux x86_64: `x86_64-linux-gnu`
- Linux ARM64: `aarch64-linux-gnu`
- Windows: `x86_64-windows-gnu`

### EmacsZ.app vs Emacs.app
Zig-built Emacs creates `EmacsZ.app` instead of `Emacs.app` to distinguish the build toolchain while maintaining identical functionality. This allows both to coexist for comparison.

## Migration Guidelines

### When Touching C Code
1. **Check Gnulib Dependencies**: Look for `#include` from `lib/` directory
2. **Evaluate Zig stdlib Replacements**: Can this be replaced with `std.mem`, `std.fs`, `std.os`?
3. **Maintain C ABI Compatibility**: Use `extern struct` when Zig must interface with C
4. **Preserve Lisp Object Tagging**: Emacs uses pointer tagging; alignment is critical

### Zig Version Constraints
- **Required**: Zig 0.16.0 (strict)
- **Documentation**: Always check latest docs via context7 (`/zig-doc` command)
- **API Changes**: Zig's Build API changes frequently; verify syntax for 0.16.0

### Gnulib Replacement Priority
High-value targets for Zig stdlib migration:
1. String operations (`lib/*str*.c`) → `std.mem`
2. File I/O (`lib/*io*.c`, `lib/*fd*.c`) → `std.fs`
3. Memory allocation (`lib/malloc/*.c`) → Custom allocator respecting Emacs GC
4. Time functions (`lib/time*.c`) → `std.time`

### Build System Migration Strategy
1. `zig build` is the single source of truth — it self-configures (runs
   `./configure` as a build step for `src/config.h`) and performs all
   compile/link. There is no `make` and no separate `./configure` step.
2. Generated headers (`config.h`, `globals.h`, `epaths.h`, the `.gl.h`)
   are produced at build time by zig-owned generators; never commit
   autoconf-generated artifacts (`config.h`, `config.in`, Makefiles).
3. Runtime gnulib functions are progressively replaced by independent
   Zig packages (e.g. `tools/gnulib-str` for `memeq`/`streq`), linked in
   place of the C source — each as its own zon dependency.
4. Fix the source, not the artifact — resolve build issues in `build.zig`,
   not by editing generated files.

## Critical Constraints

### Memory Management
- Emacs has its own garbage collector for Lisp objects
- Do NOT use Zig's general-purpose allocator for Lisp objects
- Use `extern struct` with proper alignment for Lisp object headers
- Preserve Emacs's `LISP_WORD_TAG` and `LISP_INLINE` semantics

### POSIX Compliance
- Gnulib provides strict POSIX compliance; Zig stdlib may differ
- Verify behavior at system boundaries (file I/O, signals, processes)
- Test edge cases: OOM, signal handling, Unicode filenames

### Compiler Flags
Required for Emacs compatibility:
- `-fno-common` - Emacs expects this
- `-D_GNU_SOURCE` - For GNU extensions
- Avoid `-Werror=*` - Zig's warning system differs

## Common Patterns

### Adding Zig-Compiled C Code
```bash
# Single file compilation with Zig
zig cc -target aarch64-macos-none -c foo.c -o foo.o
```

### Checking the Build
```bash
file zig-out/bin/temacs        # Linux: ELF 64-bit, non-PIE
readelf -d zig-out/bin/temacs  # Dynamic deps (zig decides the link)
```
`zig build` uses `zig cc` as the C compiler throughout — there is no
`src/Makefile` to inspect.

### Zig Documentation Lookup
Use the context7 MCP server to query Zig 0.16.0 documentation:
```
/zig-doc std.Build.Module
```

## Troubleshooting

### Build Fails with "zig: command not found"
Install Zig 0.16.0:
```bash
brew install zig        # macOS
# Or visit https://ziglang.org/download/
```

### Configure Errors on macOS
Ensure Xcode command line tools are installed:
```bash
xcode-select --install
```

### Zig Warnings During Build
Expected and generally harmless. Zig's warning system differs from GCC/Clang. Only actionable if symbols fail to link.

### Build System Integrity

- **Fix the Source, Not the Artifact**: Always resolve build-related issues by modifying **`build.zig`**. Do **not** manually edit generated files such as `Makefile`, `src/config.h`, or other Autotools output to bypass errors. 
- **Single Source of Truth**: Treat the `zig build` system as the future single source of truth. Ensure all compiler flags, include paths, and dependency logic are correctly implemented using the `std.Build` API (v0.16.0).
- **Correct Tooling Usage**: Use `zig build --summary legacy` or similar flags to debug the build graph instead of hacking temporary build directories.

### Target Triple Issues
Verify Zig supports your target:
```bash
zig targets | grep -E "arch|abi"
```

## Contributing

1. Test on your platform before pushing
2. Run `zig build check` to verify the build (578 built-in ert tests)
3. Use GitHub Actions matrix to test multiple platforms
4. Document new Zig dependencies in `CLAUDE.md` and `ZIG_BUILD.md`

## References

- `ZIG_BUILD.md` - Detailed build instructions
- `INSTALL` - Full installation guide
- `CONTRIBUTE` - Contribution guidelines
- `.github/workflows/build-zig-native.yml` - CI build (pure `zig build`)
- [Zig 0.16.0 Documentation](https://ziglang.org/documentation/0.16.0/)
