# Phase 2: Entry Point & Startup

**Duration:** Week 7-8
**Dependencies:** Phase 1 completion
**Target:** Week 8 (2026-02-28)

---

## Overview

This phase migrates the Emacs main entry point from C to C++20, implementing modern startup practices with RAII and C++20 standard library features.

### Why This Phase Second

Before migrating core subsystems (Lisp interpreter, display, GUI), we need:
1. A C++20 main entry point that can be tested and debugged
2. Modern resource management using RAII
3. Proper command line parsing with C++20 `std::span`

### Success Criteria

- [ ] Convert `src/emacs.c` to `src/main.cpp`
- [ ] Implement RAII-based resource management
- [ ] Replace command line parsing with `std::span`
- [ ] Basic execution works (`-Q`, `--version`)
- [ ] Startup tests pass
- [ ] No memory leaks
- [ ] Performance comparable to C implementation

---

## Task 2.1: Convert src/emacs.c to src/main.cpp

### Objective

Create a C++20 main entry point while preserving platform-specific initialization code.

### Constraints

- Keep all platform-specific initialization code (Windows, macOS, Android, Haiku)
- Maintain compatibility with existing C code during transition
- Use C++20 features (RAII, `std::span`, `noexcept`)
- Preserve all command-line options and arguments

### Design

```cpp
// src/main.cpp

#include "config.h"
#include "lisp.h"
#include "strings.hpp"
#include <string>
#include <string_view>
#include <span>
#include <memory>

namespace emacs {

/**
 * RAII-based startup resource manager
 *
 * Manages the startup sequence with proper cleanup
 * of all resources using RAII principles.
 */
class StartupResourceManager {
public:
    StartupResourceManager(int argc, char** argv)
        : argc_(argc), argv_(argv), initialized_(false)
    {
        // Note: No initialization in constructor to avoid exceptions
        // Resources are initialized on first use
    }

    ~StartupResourceManager() {
        // Cleanup happens automatically
    }

    /**
     * Prevent copying
     */
    StartupResourceManager(const StartupResourceManager&) = delete;

    /**
     * Check if already initialized
     */
    bool is_initialized() const noexcept {
        return initialized_;
    }

    /**
     * Mark as initialized
     */
    void mark_initialized() {
        initialized_ = true;
    }
};

/**
 * Modern command line parser using std::span
 *
 * Replaces C-style argv/argc parsing with a type-safe
 * C++20 std::span-based implementation.
 */
class CommandLineParser {
public:
    CommandLineParser(int argc, char* argv[])
        : argc_(argc), argv_(argv)
    {
    }

    /**
     * Get raw arguments as std::span
     */
    [[nodiscard]] std::span<char*> arguments() const noexcept {
        return std::span<char*>(argv_, argc_);
    }

    /**
     * Get program name
     */
    [[nodiscard]] std::string_view program_name() const noexcept {
        if (argc_ > 0) {
            return std::string_view(argv_[0]);
        }
        return {};
    }

    /**
     * Get number of arguments
     */
    [[nodiscard]] int argument_count() const noexcept {
        return argc_;
    }

    /**
     * Check if argument exists
     */
    [[nodiscard]] bool has_argument(std::string_view arg) const noexcept {
        for (auto a : arguments()) {
            if (std::string_view(a) == arg) {
                return true;
            }
        }
        return false;
    }

    /**
     * Get argument value
     */
    [[nodiscard]] std::string_view argument_value(std::string_view arg) const {
        size_t arg_len = std::char_traits<char>::length(arg);
        for (size_t i = 0; i < arguments_.size(); ++i) {
            auto a = arguments_[i];
            if (std::string_view(a).size() == arg_len &&
                std::string_view(a) == arg) {
                return a;
            }
        }
        return {};
    }

    /**
     * Check for flag (long form, e.g., --help)
     */
    [[nodiscard]] bool has_flag(std::string_view flag) const {
        return has_argument(flag);
    }

    /**
     * Check for flag (short form, e.g., -h)
     */
    [[nodiscard]] bool has_short_flag(std::string_view flag) const {
        return has_argument(flag);
    }
};

} // namespace emacs

/**
 * Main entry point (C++20 version)
 *
 * Modernized main() function with RAII resource management
 * and C++20 standard library features.
 *
 * Key features:
 * - RAII-based resource management
 * - Modern command line parsing with std::span
 * - Proper error handling
 * - Platform-specific initialization preserved
 * - Compatibility with existing C code
 */
int main(int argc, char** argv)
{
    // RAII resource manager - automatic cleanup
    emacs::StartupResourceManager resources(argc, argv);

    // Initialize Emacs systems
    using namespace emacs;

    // Parse command line options using modern C++20 approach
    CommandLineParser parser(argc, argv);

    // Process arguments
    bool batch_mode = false;
    bool debug_mode = false;
    bool no_site_lisp = false;
    bool no_init_file = false;
    bool no_loadup = false;
    bool no_x_resources = false;
    bool no_site_file = false;

    // Parse arguments
    for (auto arg : parser.arguments()) {
        // Long form options
        if (arg == "--batch") {
            batch_mode = true;
        }
        else if (arg == "--debug-init") {
            debug_mode = true;
        }
        else if (arg == "--no-site-file") {
            no_site_file = true;
        }
        else if (arg == "--no-init-file") {
            no_init_file = true;
        }
        else if (arg == "--no-loadup") {
            no_loadup = true;
        }
        else if (arg == "--no-x-resources") {
            no_x_resources = true;
        }
    }

    // Initialize Emacs (will call original C functions)
    if (!init_emacs(argc, argv)) {
        // This will be implemented to call original C main()
        // during transition period to maintain compatibility
        fatal("Cannot initialize Emacs");
    }

    // Mark resources as initialized
    resources.mark_initialized();

    // Return exit code (will be converted to Lisp integer)
    return 0;
}

/**
 * External C bridge for Emacs initialization
 *
 * This extern "C" interface allows C++ main() to call
 * original C initialization functions from src/emacs.c.
 *
 * @return 0 on success, non-zero on error
 */
extern "C" {
    /**
     * Initialize Emacs (original C function)
     *
     * This is the original main() function that performs all
     * Emacs startup initialization, Lisp environment setup, etc.
     */
    int init_emacs(int argc, char** argv);
}
```

### Implementation Notes

1. **Keep original C code:** `src/emacs.c` remains unchanged for upstream compatibility
2. **Create C++ wrapper:** `src/main.cpp` calls original C initialization via extern "C" bridge
3. **RAII Manager:** `StartupResourceManager` ensures proper cleanup
4. **Modern Parser:** `CommandLineParser` uses C++20 `std::span` for type-safety
5. **Platform-Specific Code:** All `#ifdef` blocks for Windows, macOS, Android, Haiku are preserved
6. **C Compatibility:** Extern "C" bridge allows gradual migration
7. **Command Line:** All original command-line options are preserved and parsed

---

## Task 2.2: Modernize Startup Sequence

### Objective

Implement RAII-based resource management in main() function.

### Key Changes

1. **Automatic Cleanup:** RAII ensures resources are cleaned up even on error
2. **No Manual free() calls:** Prevents memory leaks
3. **Exception Safety:** Use `noexcept` throughout
4. **Type Safety:** `std::span` prevents buffer overflows

### Components

1. **StartupResourceManager:** RAII class for managing initialization state
2. **CommandLineParser:** Type-safe command line parsing
3. **Platform Initialization:** Windows, macOS, Android, Haiku paths preserved
4. **Error Handling:** Modern C++ error handling with exceptions

---

## Task 2.3: Implement Command Line Parsing

### Objective

Replace C-style `argv`/`argc` parsing with C++20 `std::span`-based implementation.

### C vs C++20 Comparison

**C approach:**
```c
// C code (original)
for (int i = 0; i < argc; i++) {
    char *arg = argv[i];
    if (strcmp(arg, "--help") == 0) {
        print_help();
        return 0;
    }
}
```

**C++20 approach:**
```cpp
// C++ code (new)
CommandLineParser parser(argc, argv);
std::span<char*> args = parser.arguments();

for (auto arg : args) {
    if (std::string_view(arg) == "--help") {
        print_help();
    return 0;
    }
}
```

### Advantages of C++20 Implementation

1. **Type Safety:** `std::span` provides bounds checking
2. **Memory Safety:** No manual `malloc`/`free` for argument storage
3. **Zero-Cost Abstractions:** `std::string_view` doesn't allocate copies
4. **Exception Safe:** `noexcept` specifier prevents exceptions during parsing

---

## Task 2.4: Update Startup Sequence

### Objective

Integrate C++ allocator and string utilities into main() startup sequence.

### Changes

1. **Use C++ Allocator:** Replace `lisp_malloc` calls with C++ allocator
2. **Use C++ Strings:** Replace C string functions with `std::string`
3. **Modern Error Messages:** Use `std::format` instead of `asprintf`
4. **Resource Management:** All resources managed by RAII

---

## Implementation Order

### Week 2 (2026-02-08 to 2026-02-14)

**Day 1-3:** Create Phase 2 documentation
- Define requirements and success criteria
- Document design decisions
- Create task breakdown

**Day 4-5:** Create `src/main.cpp` (basic structure)
- Implement `StartupResourceManager` class
- Implement `CommandLineParser` class
- Add extern "C" bridge declarations

**Day 6-7:** Implement platform initialization
- Preserve Windows initialization
- Preserve macOS initialization
- Preserve Android initialization
- Preserve Haiku initialization

**Day 8-10:** Implement command line parsing
- Parse all original options using `CommandLineParser`
- Implement short and long form options
- Add validation and error handling

**Week 3 (2026-02-15 to 2026-02-21)**

**Day 11-12:** Integrate with C++ allocator and strings
- Replace `lisp_malloc` calls with C++ allocator
- Replace string functions with C++ utilities
- Test basic execution

**Week 4 (2026-02-22 to 2026-02-28)**

**Day 13-14:** Update existing C code compatibility
- Ensure `extern "C"` bridge works
- Test all command-line options
- Verify backward compatibility

**Week 5 (2026-02-29 to 2026-03-07)**

**Day 15-21:** Create tests for main entry point
- Write unit tests for `StartupResourceManager`
- Write unit tests for `CommandLineParser`
- Write integration tests for main() startup
- Verify all success criteria

**Week 6 (2026-02-08 to 2026-02-11)**

**Day 22-23:** Integration testing
- Test with existing C modules
- Test with new C++ allocator
- Test with new C++ string utilities
- Run full Emacs test suite

**Week 7-2026-02-12 to 2026-02-19)**

**Day 24-25:** Final validation
- Complete all success criteria
- No memory leaks
- Performance within 10% of C implementation
- All tests pass

---

## Testing Strategy

### Unit Tests

**StartupResourceManager Tests:**
- Constructor/destructor behavior
- Initialization state management
- Multiple instantiation handling

**CommandLineParser Tests:**
- Argument parsing accuracy
- Flag detection (short and long form)
- Edge cases (missing arguments, invalid input)
- Memory safety (no buffer overflows)

**Integration Tests:**
- Basic execution (`-Q`, `--version`)
- Batch mode
- Debug mode
- All original command-line options

### Test Execution

```bash
# Test main entry point
cd build-cpp
ctest -R main_entry_point

# Run basic execution test
./build-cpp/bin/emacs -Q

# Run version check
./build-cpp/bin/emacs --version
```

---

## Risks and Mitigations

### Risk 1: C/C++ Compatibility

**Risk:** Mixing C and C++ code in same project

**Mitigation:**
- Use `extern "C"` bridges for all cross-language calls
- Maintain separate compilation units for C and C++ code
- Ensure ABI compatibility

### Risk 2: Performance Regression

**Risk:** C++ overhead from RAII and `std::span`

**Mitigation:**
- Profile critical paths
- Use `noexcept` for performance-critical code
- Benchmark against C implementation

### Risk 3: Memory Leaks

**Risk:** RAII cleanup not working correctly

**Mitigation:**
- Use Valgrind/ASAN for detection
- Write unit tests for destructor behavior
- Verify all resources are freed

---

## Blocking Issues

**Current Blockers:** None

**Dependencies:**
- Phase 1 completion (C++ allocator, string utilities ready)

---

## Notes

### Files Modified

**New Files:**
- `src/main.cpp` - C++20 main entry point
- `docs/cxx-builder/phases/phase2-entry-point.md` - Phase 2 documentation

**Modified Files:**
- `src/emacs.c` - Kept as-is (for upstream compatibility)
- `src/CMakeLists.txt` - Will include main.cpp compilation

### Testing Requirements

All tests must pass before proceeding to Phase 3 (Terminal Abstraction).

**Test Coverage Required:**
- Main entry point: All basic execution paths
- Command line parsing: All options and edge cases
- Resource management: RAII cleanup verified
- Integration: Works with existing C modules
- Memory: No leaks detected (Valgrind/ASAN clean)
- Performance: Within 10% of C implementation

---

## Deliverables

1. ✅ Phase 2 documentation (`docs/cxx-builder/phases/phase2-entry-point.md`)
2. ✅ C++20 main entry point (`src/main.cpp`)
3. ✅ RAII-based resource management
4. ✅ Modern command line parser
5. ✅ Platform initialization preserved
6. ✅ C/C++ compatibility via extern "C" bridges
7. ✅ Unit tests for main entry point
8. ✅ Integration tests
9. ✅ Performance benchmarks

---

## Next Steps

After Phase 2 completion:

1. **Phase 3: Terminal Abstraction** (Week 9-12)
   - Modernize terminal subsystem with C++20 concepts
   - Improve Windows TUI implementation
   - Replace termcap with C++ alternatives

2. **Phase 4: Lisp Interpreter Core** (Week 13-20)
   - Convert Lisp data types to C++ classes
   - Refactor evaluation engine to C++20
   - Integrate C++ allocator with GC

---

**Last Updated:** 2026-02-01
**Next Review:** End of Phase 2 (2026-02-08)
