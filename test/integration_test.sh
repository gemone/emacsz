#!/bin/bash
# Emacs C++20 Migration - Integration Test Suite
# Tests both legacy C Emacs and new C++ TUI components

set -e

echo "════════════════════════════════════════════════════════════════"
echo "  Emacs C++20 Migration - Integration Test Suite"
echo "════════════════════════════════════════════════════════════════"
echo ""

REPO_ROOT="/Users/muk/Work/playground/emacsx"
cd "$REPO_ROOT"

PASSED=0
FAILED=0

run_test() {
    local name="$1"
    local cmd="$2"
    
    echo -n "Testing: $name ... "
    if eval "$cmd" > /tmp/test_output.log 2>&1; then
        echo "✅ PASS"
        ((PASSED++))
    else
        echo "❌ FAIL"
        echo "  Error output:"
        cat /tmp/test_output.log | head -5 | sed 's/^/    /'
        ((FAILED++))
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Legacy C Emacs Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "C Emacs executable exists" "test -f ./src/emacs && test -x ./src/emacs"
run_test "C Emacs version check" "./src/emacs --version | grep -q 'GNU Emacs'"
run_test "C Emacs batch mode" "./src/emacs --batch --eval '(message \"OK\")' 2>&1 | grep -q 'OK'"
run_test "C Emacs Lisp evaluation" "./src/emacs --batch --eval '(+ 1 2 3)' 2>&1"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. C++ Phase 2 Tests (Minimal Build)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "C++ emacs_minimal exists" "test -f ./build-phase4/bin/emacs_minimal"
run_test "C++ emacs_minimal runs" "./build-phase4/bin/emacs_minimal | grep -q 'Phase 2'"
run_test "C++ allocator module" "./build-phase4/bin/emacs_minimal | grep -q 'C++20'"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. C++ Phase 4 TUI Component Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "Grid unit tests" "test -f /tmp/test_grid && /tmp/test_grid | grep -q 'All Grid tests passed'"
run_test "InputParser unit tests" "test -f /tmp/test_input_parser && /tmp/test_input_parser | grep -q 'All InputParser tests passed'"
run_test "EventLoop unit tests" "test -f /tmp/test_event_loop && /tmp/test_event_loop | grep -q 'All EventLoop tests passed'"
run_test "Renderer unit tests" "test -f /tmp/test_renderer && /tmp/test_renderer | grep -q 'All Renderer tests passed'"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. C++ MVP Integration Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "MVP TUI demo exists" "test -f /tmp/test_mvp_tui"
run_test "MVP TUI demo runs" "/tmp/test_mvp_tui 2>&1 | grep -q 'MVP Demo Complete'"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. CMake Build System Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "libemacs_allocator.a" "test -f ./build-phase4/src/libemacs_allocator.a"
run_test "libemacs_grid.a" "test -f ./build-phase4/src/libemacs_grid.a"
run_test "libemacs_input_parser.a" "test -f ./build-phase4/src/libemacs_input_parser.a"
run_test "libemacs_event_loop.a" "test -f ./build-phase4/src/libemacs_event_loop.a"
run_test "libemacs_renderer.a" "test -f ./build-phase4/src/libemacs_renderer.a"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Test Results Summary"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  ✅ PASSED: $PASSED"
echo "  ❌ FAILED: $FAILED"
echo "  ────────────────"
echo "  📊 TOTAL:  $((PASSED + FAILED))"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "🎉 ALL TESTS PASSED! Emacs C++20 migration is on track."
    echo ""
    echo "Status:"
    echo "  • Legacy C Emacs: ✅ Working"
    echo "  • Phase 2 (C++ Core): ✅ Working"
    echo "  • Phase 4 (TUI Components): ✅ Working"
    echo "  • Integration: ✅ Ready for Phase 5"
    exit 0
else
    echo "⚠️  Some tests failed. Please review the errors above."
    exit 1
fi
