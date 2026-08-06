#!/bin/sh
# Generate lisp/international/{charprop,uni-*}.el from admin/unidata via
# the dumped emacs. Mirrors admin/unidata/Makefile: sed UnicodeData.txt
# -> unidata.txt (the input unidata-setup-list reads), then unidata-gen-
# file per unifile (18 of them) and finally unidata-gen-charprop.
#
# These tables are required at RUNTIME by any suite that touches
# ucs-names / char-from-name (tramp, completion, char-property tests);
# without them those suites fail to load (mass LOAD/hang). The bootstrap
# dump does not bundle them (charprop is loaded on demand, not preloaded),
# so they must be generated separately. Outputs are gitignored.
#
# Standalone (like generate-charsets/generate-unidata) -- run before
# check-all/check if the suite set needs the unicode tables.

set -u

ROOT=$(pwd)
TEMACS="$ROOT/zig-out/bin/temacs"
DUMP="$ROOT/zig-out/bin/bootstrap-emacs.pdmp"
UNIDATA=admin/unidata
OUT=lisp/international

[ -f "$TEMACS" ] || {
    echo "generate-charprop: $TEMACS missing (run 'zig build smoke' first)" >&2
    exit 1
}

SETARCH=
if command -v setarch >/dev/null 2>&1; then
    SETARCH="setarch $(uname -m) -R"
fi

# unidata.txt: sed transform of UnicodeData.txt into the sexp form
# unidata-setup-list reads ((#xCODE "field" "field" ...) per line).
sed -e 's/\([^;]*\);\(.*\)/(#x\1 "\2")/' -e 's/;/" "/g' \
    < "$UNIDATA/UnicodeData.txt" > "$UNIDATA/unidata.txt"

# Each unifile (the 18 uni-*.el enumerated by admin/unidata/Makefile's
# extraction of unidata-gen.el). The third arg is the unidata-text
# filename RELATIVE to data-dir: unidata-setup-list does
# (expand-file-name unidata-text-file unidata-dir), so a bare
# "unidata.txt" resolves under admin/unidata/ -- an absolute or
# "admin/unidata/unidata.txt" path would be double-expanded and not found.
for u in uni-name uni-category uni-combining uni-bidi uni-decomposition \
    uni-decimal uni-digit uni-numeric uni-mirrored uni-old-name \
    uni-comment uni-uppercase uni-lowercase uni-titlecase \
    uni-special-uppercase uni-special-lowercase uni-special-titlecase \
    uni-brackets; do
    [ -f "$OUT/$u.el" ] && continue
    $SETARCH "$TEMACS" --batch -L "$UNIDATA" -l unidata-gen \
        --dump-file="$DUMP" \
        --eval "(unidata-gen-file \"$OUT/$u.el\" \"$UNIDATA\" \"unidata.txt\")" >/dev/null 2>&1 ||
        { echo "generate-charprop: failed to generate $u.el" >&2; exit 1; }
done

# Non-unifile tables from the same unidata suite (admin/unidata/Makefile
# `all` target): uni-scripts (Scripts.txt), uni-confusable
# (confusables.txt), idna-mapping (IdnaMappingTable.txt) and emoji-labels
# (emoji-test.txt). textsec requires uni-confusable/idna-mapping/
# uni-scripts, char-fold builds its table from uni-scripts, and emoji.el
# loads emoji-labels -- without these the suites fail to load.
[ -f "$OUT/uni-scripts.el" ] || \
    $SETARCH "$TEMACS" --batch -L "$UNIDATA" -l unidata-gen \
        --dump-file="$DUMP" \
        --eval "(unidata-gen-scripts \"$OUT/uni-scripts.el\")" >/dev/null 2>&1 ||
        { echo "generate-charprop: failed to generate uni-scripts.el" >&2; exit 1; }

[ -f "$OUT/uni-confusable.el" ] || \
    $SETARCH "$TEMACS" --batch -L "$UNIDATA" -l unidata-gen \
        --dump-file="$DUMP" \
        --eval "(unidata-gen-confusable \"$OUT/uni-confusable.el\")" >/dev/null 2>&1 ||
        { echo "generate-charprop: failed to generate uni-confusable.el" >&2; exit 1; }

[ -f "$OUT/idna-mapping.el" ] || \
    $SETARCH "$TEMACS" --batch -L "$UNIDATA" -l unidata-gen \
        --dump-file="$DUMP" \
        --eval "(unidata-gen-idna-mapping \"$OUT/idna-mapping.el\")" >/dev/null 2>&1 ||
        { echo "generate-charprop: failed to generate idna-mapping.el" >&2; exit 1; }

[ -f "$OUT/emoji-labels.el" ] || \
    $SETARCH "$TEMACS" --batch -L "$OUT" -l emoji \
        --dump-file="$DUMP" \
        --eval "(emoji--generate-file \"$OUT/emoji-labels.el\")" >/dev/null 2>&1 ||
        { echo "generate-charprop: failed to generate emoji-labels.el" >&2; exit 1; }

# charprop.el bundles the uni-* provides; (require 'charprop) pulls them.
$SETARCH "$TEMACS" --batch -L "$UNIDATA" -l unidata-gen \
    --dump-file="$DUMP" \
    --eval "(unidata-gen-charprop \"$OUT/charprop.el\")" >/dev/null 2>&1 ||
    { echo "generate-charprop: failed to generate charprop.el" >&2; exit 1; }

echo "generate-charprop: wrote $(ls "$OUT"/uni-*.el "$OUT/charprop.el" 2>/dev/null | wc -l) files to $OUT"
