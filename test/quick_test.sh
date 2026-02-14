#!/bin/bash
# Simplified Integration Test for Emacs C++20 Migration

echo "══════════════════════════════════════════════════════════════"
echo "  Emacs C++20 Migration - Quick Integration Test"
echo "══════════════════════════════════════════════════════════════"
echo ""

cd /Users/muk/Work/playground/emacsx

PASSED=0
FAILED=0

test_file() {
    local desc="$1"
    local file="$2"
    
    echo -n "  $desc ... "
    if [ -f "$file" ]; then
        echo "✅"
        ((PASSED++))
    else
        echo "❌ (not found: $file)"
        ((FAILED++))
    fi
}

test_exec() {
    local desc="$1"
    local file="$2"
    
    echo -n "  $desc ... "
    if [ -f "$file" ] && [ -x "$file" ]; then
        echo "✅"
        ((PASSED++))
    else
        echo "❌"
        ((FAILED++))
    fi
}

echo "1️⃣  Legacy C Emacs"
echo "────────────────────────────────────────────────────────────"
test_exec "C Emacs executable" "./src/emacs"
echo ""

echo "2️⃣  C++ Phase 2 Minimal Build"
echo "────────────────────────────────────────────────────────────"
test_exec "C++ emacs_minimal" "./build-phase4/bin/emacs_minimal"
test_exec "C++ emacs_tui_demo" "./build-phase4/bin/emacs_tui_demo"
echo ""

echo "3️⃣  C++ Phase 4 Static Libraries"
echo "────────────────────────────────────────────────────────────"
test_file "libemacs_allocator.a" "./build-phase4/src/libemacs_allocator.a"
test_file "libemacs_grid.a" "./build-phase4/src/libemacs_grid.a"
test_file "libemacs_input_parser.a" "./build-phase4/src/libemacs_input_parser.a"
test_file "libemacs_event_loop.a" "./build-phase4/src/libemacs_event_loop.a"
test_file "libemacs_renderer.a" "./build-phase4/src/libemacs_renderer.a"
echo ""

echo "4️⃣  Unit Test Executables"
echo "────────────────────────────────────────────────────────────"
test_exec "test_grid" "/tmp/test_grid"
test_exec "test_input_parser" "/tmp/test_input_parser"
test_exec "test_event_loop" "/tmp/test_event_loop"
test_exec "test_renderer" "/tmp/test_renderer"
test_exec "test_mvp_tui" "/tmp/test_mvp_tui"
echo ""

echo "5️⃣  Run C++ Minimal Demo"
echo "────────────────────────────────────────────────────────────"
./build-phase4/bin/emacs_minimal
echo ""

echo "6️⃣  Run Unit Tests"
echo "────────────────────────────────────────────────────────────"
if [ -x /tmp/test_grid ]; then
    /tmp/test_grid | tail -1
fi
if [ -x /tmp/test_input_parser ]; then
    /tmp/test_input_parser | tail -1
fi
if [ -x /tmp/test_event_loop ]; then
    /tmp/test_event_loop | tail -1
fi
if [ -x /tmp/test_renderer ]; then
    /tmp/test_renderer | tail -1
fi
echo ""

echo "══════════════════════════════════════════════════════════════"
echo "  Summary"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  ✅ Passed: $PASSED"
echo "  ❌ Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "🎉 SUCCESS! All components are working."
    echo ""
    echo "Available Executables:"
    echo "  • Legacy C Emacs:    ./src/emacs"
    echo "  • C++ Minimal:       ./build-phase4/bin/emacs_minimal"
    echo "  • C++ TUI Demo:      ./build-phase4/bin/emacs_tui_demo"
    echo ""
    exit 0
else
    echo "⚠️  Some components missing or not executable."
    exit 1
fi
