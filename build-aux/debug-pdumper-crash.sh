#!/bin/sh
# debug-pdumper-crash.sh — reproduce + backtrace the intermittent
# pdumper-load crash (SIGBUS/SIGSEGV during lisp load).
#
# Background: the dumped emacs occasionally crashes on load because the
# pdumper's single-delta heap relocation is mmap-layout-sensitive (see the
# `check` step's retry-on-signal workaround in build.zig, and the
# pdumper notes in .omc/plans/zig-migration.md). This script runs the
# check-style lisp load under gdb (ASLR off via setarch, matching the
# build) in a loop until a signal crash, then prints + saves the
# backtrace to pdumper-crash-backtrace.txt.
#
# Usage: ./build-aux/debug-pdumper-crash.sh [max_attempts]   (default 10)
#
# Caveat: gdb changes the process memory layout (and disables ASLR itself),
# which can MASK this layout-sensitive crash — a clean run here does NOT
# prove the bug is gone, only that it did not reproduce under gdb. The raw
# `zig build check` retry is the load-bearing mitigation.
set -eu
cd "$(dirname "$0")/.."

[ -x ./zig-out/bin/temacs ] || { echo "Run 'zig build dump' first."; exit 1; }

EVAL='(progn (load "cl-macs") (load "cl-seq") (load "cl-extra") (require (quote ert)) (load "alloc-tests") (load "version-tests") (load "byte-run-tests") (load "float-sup-tests") (load "cl-preloaded-tests") (load "button-tests") (load "delim-col-tests") (load "color-tests") (load "custom-tests") (load "dom-tests") (load "data-tests") (load "marker-tests") (load "chartab-tests") (load "cmds-tests") (load "let-alist-tests") (load "cl-lib-tests") (load "map-tests") (load "seq-tests") (load "character-tests") (load "charset-tests") (load "json-tests") (load "fns-tests") (load "backquote-tests") (load "parse-time-tests") (load "derived-tests") (load "cond-star-tests") (load "cl-print-tests") (load "time-date-tests") (load "check-declare-tests") (load "copyright-tests") (load "easy-mmode-tests") (load "nadvice-tests") (load "pcase-tests") (load "pp-tests") (load "ring-tests") (load "rx-tests") (load "warnings-tests") (load "regexp-opt-tests") (load "range-tests") (let ((ert-batch-print-lines 0)) (ert-run-tests-batch-and-exit)))'

MAX=${1:-10}
for i in $(seq 1 "$MAX"); do
  echo "=== attempt $i/$MAX ==="
  setarch "$(uname -m)" -R gdb -batch \
    -ex 'set confirm off' \
    -ex 'set pagination off' \
    -ex 'run' \
    -ex 'bt 30' \
    -ex 'quit' \
    --args ./zig-out/bin/temacs --batch \
      -L test/src -L test/lisp -L test/lisp/emacs-lisp -L test/lisp/calendar \
      --dump-file=./zig-out/bin/bootstrap-emacs.pdmp --eval "$EVAL" \
    > pdumper-crash-backtrace.tmp 2>&1 || true
  if grep -qE 'Program received signal|SIGBUS|SIGSEGV|SIGABRT' \
      pdumper-crash-backtrace.tmp; then
    echo "*** crash on attempt $i — backtrace in pdumper-crash-backtrace.txt ***"
    cp pdumper-crash-backtrace.tmp pdumper-crash-backtrace.txt
    grep -A35 'Program received signal' pdumper-crash-backtrace.txt | head -40
    exit 0
  fi
done
echo "No crash reproduced in $MAX attempts (gdb may mask the layout-sensitive crash)."
