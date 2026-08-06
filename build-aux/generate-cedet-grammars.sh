#!/bin/sh
# Generate the cedet parser files that upstream builds from
# admin/grammars/*.{by,wy} (admin/grammars/Makefile.in). Upstream stopped
# keeping these generated files in the repository, so a source checkout
# has none of them and the cedet suites fail to load (e.g. srecode-tests:
# "Cannot open load file srecode/srt-wy"). Run before check-all; outputs
# are gitignored alongside the other generated lisp files.
#
# Each grammar declares its output file name internally, so `-o TARGET'
# only contributes the DIRECTORY (wisent-batch-make-parser uses
# (file-name-directory ...)); the declared names below must match the
# admin/grammars/Makefile.in targets.

set -u

ROOT=$(pwd)
TEMACS="$ROOT/zig-out/bin/temacs"
DUMP="$ROOT/zig-out/bin/bootstrap-emacs.pdmp"
GR=admin/grammars

[ -f "$TEMACS" ] || {
    echo "generate-cedet-grammars: $TEMACS missing (run 'zig build smoke' first)" >&2
    exit 1
}

SETARCH=
if command -v setarch >/dev/null 2>&1; then
    SETARCH="setarch $(uname -m) -R"
fi

# cl-find-class lives in cl-extra (not preloaded), and the grammar tools
# need it; the load-path must reach lisp/cedet for the -l forms.
gen () { # tool func output grammar
    tool=$1; func=$2; out=$3; src=$4
    [ -f "$out" ] && return 0
    $SETARCH "$TEMACS" --batch -L "$ROOT/lisp" -L "$ROOT/lisp/cedet" \
        --dump-file="$DUMP" -l cl-extra -l "$tool" \
        -f "$func" -o "$out" "$GR/$src" >/dev/null 2>&1 || {
        echo "generate-cedet-grammars: failed: $tool $src -> $out" >&2
        exit 1
    }
    [ -f "$out" ] || {
        echo "generate-cedet-grammars: $tool produced no $out for $src" >&2
        exit 1
    }
}

gen semantic/bovine/grammar bovine-batch-make-parser lisp/cedet/semantic/bovine/c-by.el c.by
gen semantic/bovine/grammar bovine-batch-make-parser lisp/cedet/semantic/bovine/make-by.el make.by
gen semantic/bovine/grammar bovine-batch-make-parser lisp/cedet/semantic/bovine/scm-by.el scheme.by
gen semantic/wisent/grammar wisent-batch-make-parser lisp/cedet/semantic/grammar-wy.el grammar.wy
gen semantic/wisent/grammar wisent-batch-make-parser lisp/cedet/semantic/wisent/javat-wy.el java-tags.wy
gen semantic/wisent/grammar wisent-batch-make-parser lisp/cedet/semantic/wisent/js-wy.el js.wy
gen semantic/wisent/grammar wisent-batch-make-parser lisp/cedet/semantic/wisent/python-wy.el python.wy
gen semantic/wisent/grammar wisent-batch-make-parser lisp/cedet/srecode/srt-wy.el srecode-template.wy

echo "generate-cedet-grammars: wrote $(ls lisp/cedet/semantic/*-wy.el \
    lisp/cedet/semantic/bovine/*-by.el lisp/cedet/semantic/wisent/*-wy.el \
    lisp/cedet/srecode/srt-wy.el 2>/dev/null | wc -l) parser files"
