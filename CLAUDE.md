# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Emacs Zig Migration

This repository contains GNU Emacs with an ongoing effort to modernize the build system and codebase by migrating from Autotools + Gnulib to Zig.

### Current Status: Phase 1 Complete, Phase 2 In Progress
- **Phase 1**: Replace default C compiler with `zig cc` ✅ Complete
- **Phase 2**: Create native `build.zig` and begin migrating C modules 🚧 In Progress
- **Phase 3**: Complete Autotools/Gnulib replacement 🔮 Future

## Development Commands

### Primary Build Workflow (Current - Using Zig as C Compiler)
```bash
# Initial setup (run after cloning or modifying configure.ac)
./autogen.sh

# Configure with Zig (auto-detected if available)
./configure --with-ns --without-x    # macOS
./configure --with-x --without-ns    # Linux

# Build
make -j$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null)

# Install (macOS - creates EmacsZ.app)
make install

# Run
open nextstep/EmacsZ.app                 # macOS
./src/emacs --batch --eval "(...)"       # Any platform
```

### Testing
```bash
# Verify Zig is being used
grep "^CC " src/Makefile    # Should show: CC = zig cc

# Verify binary architecture
file nextstep/EmacsZ.app/Contents/MacOS/Emacs    # macOS
file src/emacs                                   # Linux

# Run local Zig configuration tests
./test-zig-build.sh

# Test GitHub Actions workflows locally (requires act)
act -j build --matrix os:macos
```

### CI/CD Testing
GitHub Actions workflows are in `.github/workflows/`:
- `build-zig.yml` - Multi-platform build matrix (macOS, Linux, Windows, ARM64)
- `build-simple.yml` - Quick verification
- Use `act` to test workflows locally before pushing

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
1. Don't break existing `./configure && make` workflow
2. Gradually add `build.zig` steps for individual modules
3. Use `zig cc` compatibility as bridge during transition
4. Test on all target platforms (macOS ARM64/x86_64, Linux, Windows)

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

### Checking if Zig is Being Used
```bash
# In Makefile
grep "^CC.*zig" src/Makefile

# In binary
otool -L nextstep/EmacsZ.app/Contents/MacOS/Emacs  # macOS
readelf -d src/emacs                               # Linux
```

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
2. Run `./test-zig-build.sh` to verify configuration
3. Use GitHub Actions matrix to test multiple platforms
4. Document new Zig dependencies in `CLAUDE.md` and `ZIG_BUILD.md`

## References

- `ZIG_BUILD.md` - Detailed build instructions
- `INSTALL` - Full installation guide
- `CONTRIBUTE` - Contribution guidelines
- `.github/workflows/build-zig.yml` - CI/CD examples
- [Zig 0.16.0 Documentation](https://ziglang.org/documentation/0.16.0/)



