#!/bin/bash
set -e

# Ensure temacs is built
if [ ! -f "zig-out/bin/temacs" ]; then
    echo "Error: temacs not found. Please run: zig build"
    exit 1
fi

# Set test environment
export EMACS_TEST_DIRECTORY="$(pwd)/test"
export EMACS="$(pwd)/zig-out/bin/temacs"

echo "=== Running Emacs Tests ==="
echo "EMACS: $EMACS"
echo "TEST_DIR: $EMACS_TEST_DIRECTORY"
echo ""

# Run a simple test to verify functionality
cd test

echo "Test: Basic ERT functionality (abbrev-tests)"
$EMACS --batch \
    -L "$(pwd)/lisp" \
    -L "$(pwd)/../lisp" \
    -l ert \
    -l lisp/abbrev-tests.el \
    -f ert-run-tests-batch-and-exit \
    2>&1 | tee test-abbrev.log

echo ""
echo "=== Tests Complete ==="
echo "Results: test/*.log"
