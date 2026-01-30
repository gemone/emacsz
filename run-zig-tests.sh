#!/bin/bash
# Zig native test runner
# Runs all tests using Zig-built temacs

set -e

EMACS="$(pwd)/zig-out/bin/temacs"
TEST_DIR="$(pwd)/test"
SELECTOR="${TEST_SELECTOR:-(not (or (tag :expensive-test) (tag :unstable))}"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Zig Build - All Tests                            ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "EMACS: $EMACS"
echo "TEST_DIR: $TEST_DIR"
echo "SELECTOR: $SELECTOR"
echo ""

cd "$TEST_DIR"

# Find all test files
TEST_FILES=$(find . -name "*-tests.el" -type f | sort)
TOTAL=$(echo "$TEST_FILES" | wc -l | awk '{print $1}')
PASSED=0
FAILED=0

for i in $(seq 1 "$TOTAL"); do
    TEST_FILE=$(echo "$TEST_FILES" | sed -n "${i}p")
    if [ ! -f "$TEST_FILE" ]; then
        echo "[$i/$TOTAL] ⊘ SKIPPED $TEST_FILE (file not found)"
        continue
    fi

    TEST_NAME=$(basename "$TEST_FILE" .el)

    echo "[$i/$TOTAL] Running $TEST_NAME..."

    if HOME=/nonexistent EMACS_TEST_DIRECTORY="$(pwd)" "$EMACS" --batch \
        -L . -L ../lisp \
        -l ert \
        -l "$TEST_FILE" \
        -f ert-run-tests-batch-and-exit \
        --eval "(ert-run-tests-batch-and-exit (quote $SELECTOR))" \
        2>&1 | tee "${TEST_NAME}.log" | tail -5; then
        echo "      ✓ PASSED"
        ((PASSED++))
    else
        echo "      ✗ FAILED (see ${TEST_NAME}.log)"
        ((FAILED++))
    fi
done

echo ""
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║                        Test Summary                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Total:  $TOTAL"
echo "Passed:  $PASSED"
echo "Failed:  $FAILED"
echo ""
echo "✓ Test complete!"
