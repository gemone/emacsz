# Emacs Zig Migration Project - CLAUDE.md

## Project Vision
This project aims to modernize **Emacs** by replacing the legacy build system (Autotools + Gnulib) and C source code with **Zig**. We are currently in the initial phase of this transition.

## Current Milestone: Step 1
- **Objective**: Replace the default C compiler with `zig cc`.
- **Focus**: Maintain compatibility with existing C headers while orchestrating the build via Zig's toolchain.

## Technical Constraints & Environment
- **Zig Version**: `0.15.2` (Required).
- **Documentation**: Always consult the latest documentation via `zig doc context7` before suggesting Zig code or build configurations. Avoid deprecated APIs from older Zig versions.
- **Build System**: Transitioning from `./configure` and `make` to a native `build.zig` infrastructure.

## Development Workflow
### Build Commands
- Primary build: `zig build`
- C integration: Use `zig cc` flags compatible with Emacs's specific requirements (e.g., `-fno-common`, `-D_GNU_SOURCE`).

### Code Style & Guidelines
- **C Code**: Adhere to the existing GNU coding standards used in the Emacs repository.
- **Zig Code**: Must follow `zig fmt` standards.
- **Interoperability**: When wrapping C structs in Zig, use `extern struct` and ensure proper alignment for Emacs's Lisp object tagging system.

### Critical Notes
- **Gnulib Replacement**: Be cautious when replacing Gnulib functions with Zig standard library equivalents; ensure POSIX compliance is maintained where Emacs expects it.
- **Context Awareness**: Always remember that this is a gradual migration. Do not suggest breaking changes that prevent the project from compiling as a hybrid C/Zig codebase.
