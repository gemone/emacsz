#!/bin/sh
# check-all.sh — full-suite ert discovery with NO skip.
#
# Unlike `zig build check` (a hand-picked set of 40 stable suites), this
# runs EVERY *-tests.el under test/ in its own temacs process, under a
# per-suite timeout, and classifies the outcome so that one bad suite
# can never hide another. The point is to surface every failure so it
# can drive the next migration phase — nothing is excluded up front.
#
# Classification (exit-code based):
#   PASS  rc=0     all ert tests in the suite passed
#   FAIL  rc=1     ert reported unexpected results
#   HANG  rc=124   exceeded the per-suite timeout (likely eval loop)
#   CRASH rc>=128  temacs died on a signal (SIGABRT/SIGSEGV/SIGBUS/...)
#   LOAD  other    temacs exited without running ert (load/setup error)
#
# Output: a TSV stream to stdout (status<TAB>rc<TAB>suite<TAB>detail)
# plus the full per-suite log under zig-out/check-all/<suite>.out, and a
# summary at the end. Mirrors the `make check` environment (LANG=C,
# HOME=/nonexistent, EMACS_TEST_DIRECTORY) with a per-suite load-path
# (see the loop) so any (require ..) / (load ..) resolves without an
# install.
#
# Env overrides:
#   CHECK_ALL_TIMEOUT  per-suite timeout in seconds (default 90)
#   CHECK_ALL_FILTER   grep -E pattern; if set, only matching suite paths run

set -u

ROOT=$(pwd)
TEMACS="$ROOT/zig-out/bin/temacs"
# Overridable via CHECK_ALL_DUMP so a caller can pin a stable copy and
# avoid races with a concurrent re-dump overwriting the live pdmp.
DUMP=${CHECK_ALL_DUMP:-$ROOT/zig-out/bin/bootstrap-emacs.pdmp}
OUTDIR="$ROOT/zig-out/check-all"
mkdir -p "$OUTDIR"

TIMEOUT=${CHECK_ALL_TIMEOUT:-90}
FILTER=${CHECK_ALL_FILTER:-}

# load-path is built PER SUITE inside the loop (the bootstrap default
# load-path, which already carries lisp/, plus test/ and the suite's
# own dir). Two reasons not to use one global -L over all ~500 test/
# subdirs here: (1) every require then crawls hundreds of dirs and
# cl-macs loading hangs outright; (2) name pollution — test/ has files
# like comp-tests.el/macro-aux.el that shadow real modules. cl-*/ert
# resolve via the bootstrap dump's default load-path (lisp/emacs-lisp/).

if command -v setarch >/dev/null 2>&1; then
    SETARCH="setarch $(uname -m) -R"
else
    SETARCH=""
fi

# cl-* must be preloaded explicitly: the bootstrap dump has ldefs_boot
# only, so cl-lib is not autoloaded, and many test bodies expand cl
# macros at load time.
PRE='(progn (load "cl-macs") (load "cl-seq") (load "cl-extra") (require (quote ert)))'

suites=$(find test -name '*-tests.el' 2>/dev/null | sort)
if [ -n "$FILTER" ]; then
    suites=$(printf '%s\n' "$suites" | grep -E "$FILTER" || true)
fi

total=$(printf '%s\n' "$suites" | grep -c .)
printf 'check-all: %d suites, timeout=%ss\n' "$total" "$TIMEOUT" >&2

pass=0; fail=0; hang=0; crash=0; loaderr=0; n=0
for suite in $suites; do
    n=$((n+1))
    rel=${suite#test/}            # src/editfns-tests.el
    rel=${rel%.el}                # src/editfns-tests
    suitedir=$(dirname "$ROOT/$suite")
    # Absolute path, no extension: temacs rewrites default-directory
    # during startup, so a relative (load "test/...") can fail to resolve
    # and emit a huge file-error backtrace. (load "/abs/.../suite") finds
    # the .el directly regardless of default-directory.
    loadtarget=$ROOT/${suite%.el}
    # Per-suite load-path (see note above): bootstrap default + test/ +
    # this suite's dir. Keeps every require searching ~3 dirs, not 500.
    LP="-L $ROOT/test -L $suitedir"
    # Mirror test/Makefile.in's SELECTOR_DEFAULT so suites behave like
    # `make check`: :unstable and :expensive-test tests are skipped, not
    # run (e.g. srecode-field-utest-impl is a known-broken :unstable test).
    form="(progn ${PRE} (load \"${loadtarget}\") (let ((ert-batch-print-lines 0)) (ert-run-tests-batch-and-exit (quote (not (or (tag :expensive-test) (tag :unstable)))))))"
    # Retry on signal death only (the pdumper's single-delta heap
    # relocation is intermittently mis-applied under load, killing temacs
    # with SIGBUS/SIGSEGV/SIGABRT during lisp load -- the same flakiness
    # the `check` step retries). A real suite result exits 0/1/255, and a
    # timeout-KILL is SIGKILL (137), so neither is retried: transient
    # signal deaths must not inflate the CRASH bucket.
    attempt=0; rc=0; out=
    while :; do
        attempt=$((attempt+1))
        out=$(LANG=C HOME=/nonexistent EMACS_TEST_DIRECTORY="$ROOT/test" \
            timeout -s KILL "$TIMEOUT" \
            sh -c 'ulimit -s unlimited 2>/dev/null; '"$SETARCH"' "$1" --batch '"$LP"' --dump-file="$2" --eval "$3"' \
            _ "$TEMACS" "$DUMP" "$form" 2>&1)
        rc=$?
        if [ "$rc" -lt 128 ] || [ "$rc" -gt 192 ] || [ "$rc" -eq 137 ]; then
            break
        fi
        [ "$attempt" -ge "${CHECK_ALL_RETRIES:-3}" ] && break
        echo "check-all: $rel died with signal (rc=$rc) on attempt $attempt/${CHECK_ALL_RETRIES:-3}; retrying (pdumper relocation flakiness)" >&2
    done
    case "$rc" in
        0)   status=PASS;  pass=$((pass+1)) ;;
        1)   status=FAIL;  fail=$((fail+1)) ;;
        124) status=HANG;  hang=$((hang+1)) ;;   # timeout, default signal
        137) status=HANG;  hang=$((hang+1)) ;;   # timeout -s KILL (used here)
        # Signal death is rc = 128+signum; real-time signals top out at 64
        # (rc 192). temacs batch errors exit with codes like 255, which are
        # NOT signals -- classify those as LOAD, not CRASH.
        *)   if [ "$rc" -ge 128 ] && [ "$rc" -le 192 ]; then status=CRASH; crash=$((crash+1)); else status=LOAD; loaderr=$((loaderr+1)); fi ;;
    esac
    detail=
    case "$status" in
        FAIL)  detail=$(printf '%s\n' "$out" | grep -oE '[0-9]+ unexpected[^,)]*' | tail -1) ;;
        HANG)  detail="timeout ${TIMEOUT}s" ;;
        CRASH) detail="signal $((rc-128)) (rc=$rc)" ;;
        LOAD)  detail=$(printf '%s\n' "$out" | grep -iE 'error|void-function|cannot open|wrong-type-argument|no catch' | head -1 | cut -c1-80) ;;
    esac
    printf '%s\trc=%s\t%s\t%s\n' "$status" "$rc" "$rel" "$detail"
    log=$OUTDIR/$(printf '%s' "$rel" | tr '/' '_').out
    printf '%s' "$out" > "$log"
done

echo
echo "=== check-all SUMMARY ==="
echo "total=$n  pass=$pass  fail=$fail  hang=$hang  crash=$crash  load=$loaderr"
