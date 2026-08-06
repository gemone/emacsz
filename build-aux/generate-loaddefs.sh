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

# SUBDIRS_ALMOST (lisp/Makefile.in) is every lisp/ directory recursively,
# INCLUDING the root: `find ${srcdir} -type d` minus the exact obsolete/
# and term/ dirs. The root scan is what creates the top-level
# *-loaddefs.el files declared via generated-autoload-file file-locals
# (ibuffer-loaddefs.el, ps-print-loaddefs.el) and nested-dir scans create
# e.g. cedet/srecode/srecode-loaddefs.el; without them the suites that
# (require 'foo-loaddefs) fail to load. The batch function reads these
# paths from command-line-args-left and scrapes autoload cookies into
# per-dir *-loaddefs.el + lisp/loaddefs.el.
SUBDIRS=$(find . -type d ! -path './obsolete' ! -path './term' \
    -printf '%p ' | sort | tr '\n' ' ')

# Force a FULL regeneration: with an existing loaddefs.el, the generator
# runs in "updating" mode and silently skips every source file older than
# it (so a fresh checkout would never create the missing *-loaddefs.el
# files). Mirroring lisp/Makefile.in's autoloads-force, delete the main
# output first so updating=nil and every file is rescanned.
rm -f loaddefs.el

$SETARCH "$TEMACS" --batch -L . \
    -l emacs-lisp/loaddefs-gen.el \
    --dump-file="$DUMP" \
    -f loaddefs-generate--emacs-batch $SUBDIRS

echo "generate-loaddefs: $(find . -name '*-loaddefs.el' | wc -l) *-loaddefs.el + loaddefs.el in lisp/"
