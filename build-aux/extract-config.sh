#!/bin/bash
# Extract configuration from configure.ac and src/config.h

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TOP_DIR"

# Extract version (for now, parse from src/emacs.c version)
VERSION=$(grep "emacs_version" src/emacs.c | grep 's *=' | sed 's/.*"\([^"]*\)".*/\1/' | head -1)
if [ -z "$VERSION" ]; then
    VERSION="31.0.50"
fi
echo "VERSION=$VERSION"

# Extract configuration from src/config.h
if [ -f "src/config.h" ]; then
    CONFIGURATION=$(grep "#define EMACS_CONFIGURATION " src/config.h | sed 's/.*"\(.*\)".*/\1/')
    echo "CONFIGURATION=$CONFIGURATION"
else
    CONFIGURATION="unknown"
    echo "CONFIGURATION=$CONFIGURATION"
fi

# Output paths for use in build.zig
echo "archlibdir=libexec/emacs/\${VERSION}/\${CONFIGURATION}"
echo "etcdir=share/emacs/\${VERSION}/etc"
echo "lispdir=share/emacs/\${VERSION}/lisp"
echo "bindir=bin"
