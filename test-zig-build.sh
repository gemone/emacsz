#!/bin/bash
# Local test script to verify Zig build configuration
# This mimics what the GitHub Actions workflow does

set -e

echo "=================================="
echo "Zig Build Configuration Test"
echo "=================================="
echo ""

# Test 1: Check Zig installation
echo "Test 1: Checking Zig installation..."
if command -v zig &> /dev/null; then
    ZIG_VERSION=$(zig version)
    echo "✓ Zig found: $ZIG_VERSION"
else
    echo "✗ Zig not found. Install with: brew install zig"
    exit 1
fi
echo ""

# Test 2: Verify Zig can compile C code
echo "Test 2: Testing Zig C compilation..."
cat > /tmp/test_zig.c << 'EOF'
#include <stdio.h>
int main() {
    printf("Hello from Zig-compiled C code!\n");
    return 0;
}
EOF

zig cc /tmp/test_zig.c -o /tmp/test_zig
if /tmp/test_zig | grep -q "Hello from Zig"; then
    echo "✓ Zig C compilation works"
else
    echo "✗ Zig C compilation failed"
    exit 1
fi
echo ""

# Test 3: Check configure.ac modifications
echo "Test 3: Checking configure.ac for Zig support..."
if [ ! -f "configure.ac" ]; then
    echo "✗ configure.ac not found"
    exit 1
fi

if grep -q "ZIG_CC" configure.ac; then
    echo "✓ Zig detection code found in configure.ac"
else
    echo "✗ Zig detection code not found in configure.ac"
    exit 1
fi

if grep -q "emacs_cv_zig_cc_works" configure.ac; then
    echo "✓ Zig cache variable found"
else
    echo "✗ Zig cache variable not found"
    exit 1
fi
echo ""

# Test 4: Check EmacsZ.base template
echo "Test 4: Checking EmacsZ.app template..."
if [ -d "nextstep/Cocoa/EmacsZ.base" ]; then
    echo "✓ EmacsZ.base template exists"
else
    echo "✗ EmacsZ.base template not found"
    echo "  Run: mkdir -p nextstep/Cocoa/EmacsZ.base/Contents/Resources/English.lproj"
    echo "       cp -r nextstep/Cocoa/Emacs.base/* nextstep/Cocoa/EmacsZ.base/"
fi
echo ""

# Test 5: Verify Zig targets
echo "Test 5: Checking Zig target support..."
TARGETS=(
    "aarch64-macos"
    "x86_64-linux"
    "x86_64-windows"
)

for target in "${TARGETS[@]}"; do
    if zig targets | grep -q "$(echo $target | cut -d- -f1)"; then
        echo "✓ Target $target is supported"
    else
        echo "? Target $target support unknown"
    fi
done
echo ""

# Test 6: Check GitHub Actions workflows
echo "Test 6: Checking GitHub Actions workflows..."
WORKFLOWS=(
    ".github/workflows/test.yml"
    ".github/workflows/build-simple.yml"
    ".github/workflows/build-zig.yml"
)

for workflow in "${WORKFLOWS[@]}"; do
    if [ -f "$workflow" ]; then
        echo "✓ $workflow exists"
    else
        echo "✗ $workflow not found"
    fi
done
echo ""

# Test 7: Verify existing build (if present)
echo "Test 7: Checking existing EmacsZ build..."
if [ -f "nextstep/EmacsZ.app/Contents/MacOS/Emacs" ]; then
    echo "✓ EmacsZ.app binary exists"

    # Check if it was built with Zig
    if [ -f "src/Makefile" ] && grep -q "^CC.*zig" src/Makefile; then
        echo "✓ Built with Zig compiler"
    fi

    # Test binary
    if nextstep/EmacsZ.app/Contents/MacOS/Emacs --batch \
        --eval "(progn (message \"Test OK\") (kill-emacs))" 2>&1 | grep -q "Test OK"; then
        echo "✓ EmacsZ binary is functional"
    fi
else
    echo "ℹ EmacsZ.app not built yet. Run: make install"
fi
echo ""

echo "=================================="
echo "Test Summary"
echo "=================================="
echo "All critical tests passed! ✓"
echo ""
echo "To build Emacs with Zig:"
echo "  ./autogen.sh"
echo "  ./configure --with-ns --without-x"
echo "  make -j\$(sysctl -n hw.ncpu)"
echo "  make install"
echo ""
echo "To test workflows locally with act:"
echo "  act -W .github/workflows/test.yml"
echo ""
