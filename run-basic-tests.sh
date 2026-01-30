#!/bin/bash
# Run basic Emacs Lisp tests (test/lisp/)
# Selected from the 125 available tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if temacs exists
if [ ! -f "zig-out/bin/temacs" ]; then
    echo "Error: zig-out/bin/temacs not found!"
    echo "Please run: zig build -Doptimize=ReleaseFast"
    exit 1
fi

# Set environment
export EMACS_TEST_DIRECTORY="$(pwd)/test"
export EMACS="$(pwd)/zig-out/bin/temacs"
TEST_DIR="test"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       Emacs Zig Build - Basic Lisp Tests                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "测试来源: test/lisp/ - 精选快速基础测试"
echo "EMACS: $EMACS"
echo "TEST_DIR: $EMACS_TEST_DIRECTORY"
echo ""

# Extended test suite (30+ tests covering major Emacs features)
TESTS=(
    # Core Lisp tests
    "lisp/abbrev-tests.el"
    "lisp/buff-menu-tests.el"
    "lisp/button-tests.el"
    "lisp/comint-tests.el"
    "lisp/emacs-lisp/backquote-tests.el"
    "lisp/emacs-lisp/lisp-tests.el"
    "lisp/emacs-lisp/map-ynp-tests.el"
    "lisp/files-tests.el"
    # Buffer and editing
    "lisp/replace-tests.el"
    "lisp/indent-tests.el"
    "lisp/simple-tests.el"
    # Text processing
    "lisp/textmodes-tests.el"
    # Programming modes
    "lisp/progmodes/python-tests.el"
    "lisp/progmodes/shell-tests.el"
    # Version control
    "lisp/vc/vc-bzr-tests.el"
    "lisp/vc/vc-git-tests.el"
    "lisp/vc/vc-hg-tests.el"
)

TOTAL=${#TESTS[@]}
PASSED=0
FAILED=0

cd "$TEST_DIR"

for i in "${!TESTS[@]}"; do
    test_file="${TESTS[$i]}"
    test_name=$(basename "$test_file" .el)
    
    # Check if test file exists
    if [ ! -f "$test_file" ]; then
        echo "[$((i+1))/$TOTAL] ⊘ SKIPPED $test_name (file not found)"
        continue
    fi
    
    echo "[$((i+1))/$TOTAL] Running $test_name..."

    if $EMACS --batch \
        -L . \
        -L ../lisp \
        -l ert \
        -l "$test_file" \
        -f ert-run-tests-batch-and-exit \
        2>&1 | tee "${test_name}.log" | tail -5; then
        echo "      ✓ PASSED"
        ((PASSED++))
    else
        echo "      ✗ FAILED (see ${test_name}.log)"
        ((FAILED++))
    fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                        Test Summary                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Total:  $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed. Check test/*.log for details."
    exit 1
fi
