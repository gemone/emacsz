#!/bin/sh
# Wrapper that launches the dumped bootstrap emacs (bootstrap-emacs.pdmp)
# via temacs. Installed as zig-out/bin/emacs so a user (and the planned
# lisp bootstrap) can invoke `emacs` like a normal editor command, with
# the pdmp and temacs located relative to this script -- no hardcoded
# absolute paths, runnable from any CWD.
#
# Run `zig build dump` first to produce bootstrap-emacs.pdmp.

# Resolve the directory of this script ($0), following symlinks.
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

TEMACS="$here/temacs"
PDMP="$here/bootstrap-emacs.pdmp"

if [ ! -f "$TEMACS" ]; then
    echo "emacs: temacs not found at $TEMACS" >&2
    echo "emacs: run 'zig build' first." >&2
    exit 1
fi
if [ ! -f "$PDMP" ]; then
    echo "emacs: dump file not found at $PDMP" >&2
    echo "emacs: run 'zig build dump' first." >&2
    exit 1
fi

# epaths.h build-tree paths locate lisp/etc under the source tree by
# default (I7), so the wrapper works from any CWD WITHOUT setting
# EMACSLOADPATH/EMACSDATA. An empty EMACSDATA is treated by Emacs as a
# real (but wrong) value, so only export these when the caller supplies
# explicit EMACS_LISP_DIR/EMACS_DATA_DIR overrides (relocatability/testing)
# -- otherwise leave them unset and let epaths.h drive.
if [ -n "${EMACS_LISP_DIR:-}" ]; then
    EMACSLOADPATH="$EMACS_LISP_DIR"
    export EMACSLOADPATH
fi
if [ -n "${EMACS_DATA_DIR:-}" ]; then
    EMACSDATA="$EMACS_DATA_DIR"
    export EMACSDATA
fi

# Disable ASLR on Linux for reliable pdumper relocation (the dump/load
# addresses differ under ASLR); fall back to plain temacs where
# setarch is absent.
if command -v setarch >/dev/null 2>&1; then
    exec setarch "$(uname -m)" -R "$TEMACS" --dump-file="$PDMP" "$@"
else
    exec "$TEMACS" --dump-file="$PDMP" "$@"
fi
