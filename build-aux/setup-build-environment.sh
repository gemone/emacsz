#!/bin/sh
# Simple setup for Zig native build
# Run autogen and configure with TUI mode (no GUI)

set -e

echo "Setting up build environment..."

# Run autogen if needed
if [ ! -f configure ]; then
    echo "Running autogen.sh..."
    ./autogen.sh
fi

# Configure for TUI mode (works on all platforms)
# Disable modules since they're not yet supported in Zig build
./configure --without-x --without-ns --without-modules

echo "Setup complete!"
echo "Generated: src/config.h"
