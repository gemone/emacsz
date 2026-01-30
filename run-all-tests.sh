#!/bin/bash
# Run selected Emacs tests

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
echo "║          Emacs Zig Build - Test Suite                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "EMACS: $EMACS"
echo "TEST_DIR: $EMACS_TEST_DIRECTORY"
echo ""

# List of quick tests to run
TESTS=(
    "lisp/abbrev-tests.el"
    "lisp/buff-menu-tests.el"
)

TOTAL=${#TESTS[@]}
PASSED=0
FAILED=0

cd "$TEST_DIR"

for i in "${!TESTS[@]}"; do
    test_file="${TESTS[$i]}"
    test_name=$(basename "$test_file" .el)
    
    echo "[$((i+1))/$TOTAL] Running $test_name..."
    
    if $EMACS --batch \
        -L "$(pwd)/lisp" \
        -L "$(pwd)/../lisp" \
        -l ert \
        -l "$test_file" \
        -f ert-run-tests-batch-and-exit \
        > "${test_name}.log" 2>&1; then
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
