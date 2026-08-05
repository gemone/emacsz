#!/bin/sh
# Generate lisp/loaddefs.el + per-subdir *-loaddefs.el (autoload cookies)
# via the dumped emacs. Mirrors lisp/Makefile.in's `autoloads` target:
#   ${emacs} -l loaddefs-gen.el -f loaddefs-generate--emacs-batch ${SUBDIRS_ALMOST}
#
# Required at RUNTIME by suites that (require 'foo-loaddefs) (calendar,
# calc, org, ...); without these files those suites fail to load with
# "Cannot open load file: X-loaddefs" -- the single biggest failure
# bucket in check-all (66 LOAD). The bootstrap dump does not bundle them
# (autoloads are generated, not preloaded). Outputs are gitignored.
#
# Standalone (like generate-charsets/generate-charprop); run before
# check-all if the suite set needs autoloads.

set -u

ROOT=$(pwd)
TEMACS="$ROOT/zig-out/bin/temacs"
DUMP="$ROOT/zig-out/bin/bootstrap-emacs.pdmp"

[ -f "$TEMACS" ] || {
    echo "generate-loaddefs: $TEMACS missing (run 'zig build smoke' first)" >&2
    exit 1
}

SETARCH=
if command -v setarch >/dev/null 2>&1; then
    SETARCH="setarch $(uname -m) -R"
fi

# loaddefs-generate--emacs-batch sets default-directory to lisp-directory
# itself, so run from lisp/.
cd "$ROOT/lisp" || exit 1

# SUBDIRS_ALMOST (lisp/Makefile.in): all lisp/ subdirs except obsolete,
# term, leim. The batch function reads these from command-line-args-left
# and scrapes autoload cookies into per-dir *-loaddefs.el + loaddefs.el.
SUBDIRS=$(find . -mindepth 1 -maxdepth 1 -type d \
    ! -name obsolete ! -name term ! -name leim -printf '%f\n' | sort | tr '\n' ' ')

$SETARCH "$TEMACS" --batch -L . \
    -l emacs-lisp/loaddefs-gen.el \
    --dump-file="$DUMP" \
    -f loaddefs-generate--emacs-batch $SUBDIRS

echo "generate-loaddefs: $(find . -name '*-loaddefs.el' | wc -l) *-loaddefs.el + loaddefs.el in lisp/"
