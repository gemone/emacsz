#!/bin/bash
# Clean build cache files, preserving core Zig build configuration

echo "=== Cleaning Emacs Zig Build Caches ==="
echo ""

# Clean Zig build cache
if [ -d ".zig-cache" ]; then
    size=$(du -sh .zig-cache | cut -f1)
    echo "Removing .zig-cache/ ($size)"
    rm -rf .zig-cache
fi

# Clean Zig build output
if [ -d "zig-out" ]; then
    size=$(du -sh zig-out | cut -f1)
    echo "Removing zig-out/ ($size)"
    rm -rf zig-out
fi

# Clean autotools cache
if [ -d "autom4te.cache" ]; then
    size=$(du -sh autom4te.cache | cut -f1)
    echo "Removing autom4te.cache/ ($size)"
    rm -rf autom4te.cache
fi

# Clean autotools build directory
if [ -d "build" ]; then
    size=$(du -sh build | cut -f1)
    echo "Removing build/ ($size)"
    rm -rf build
fi

# Clean temporary temacs binary in src/
if [ -f "src/temacs" ]; then
    echo "Removing src/temacs (temporary binary)"
    rm -f src/temacs
fi

# Clean any .pdmp files in src/
if ls src/*.pdmp 2>/dev/null; then
    echo "Removing src/*.pdump files"
    rm -f src/*.pdmp
fi

# Clean libexec directory created in project root
if [ -d "libexec" ]; then
    echo "Removing libexec/ (test directory)"
    rm -rf libexec
fi

echo ""
echo "=== Cleanup Complete ==="
echo "Preserved core files:"
echo "  - build.zig (Zig build configuration)"
echo "  - build-config/ (generated source lists)"
echo "  - build-aux/ (build scripts)"
echo "  - All source code (src/, lib/, lisp/)"
echo ""
echo "To rebuild: zig build -Doptimize=ReleaseFast"
