#!/bin/sh
# Generate Gnulib .gl.h internal header files
# These files are needed by Zig compilation but may not be generated
# automatically in all environments.

set -e

echo "Generating Gnulib .gl.h headers..."

# Ensure directory exists
mkdir -p lib/malloc

# Generate malloc/dynarray.gl.h
if [ -f lib/malloc/dynarray.h ]; then
    echo "  GEN malloc/dynarray.gl.h"
    sed -e 1h -e '1s,.*,/* DO NOT EDIT! GENERATED AUTOMATICALLY! */,' -e 1G \
        -e '/libc_hidden_proto/d' \
        lib/malloc/dynarray.h > lib/malloc/dynarray.gl.h
else
    echo "  SKIP malloc/dynarray.gl.h (source not found)"
fi

# Generate malloc/dynarray-skeleton.gl.h
if [ -f lib/malloc/dynarray-skeleton.c ]; then
    echo "  GEN malloc/dynarray-skeleton.gl.h"
    sed -e 1h -e '1s,.*,/* DO NOT EDIT! GENERATED AUTOMATICALLY! */,' -e 1G \
        -e 's|<malloc/dynarray\.h>|<malloc/dynarray.gl.h>|g' \
        -e 's|__attribute_maybe_unused__|_GL_ATTRIBUTE_MAYBE_UNUSED|g' \
        -e 's|__attribute_nonnull__|_GL_ATTRIBUTE_NONNULL|g' \
        -e 's|__attribute_warn_unused_result__|_GL_ATTRIBUTE_NODISCARD|g' \
        -e 's|__glibc_likely|_GL_LIKELY|g' \
        -e 's|__glibc_unlikely|_GL_UNLIKELY|g' \
        lib/malloc/dynarray-skeleton.c > lib/malloc/dynarray-skeleton.gl.h
else
    echo "  SKIP malloc/dynarray-skeleton.gl.h (source not found)"
fi

# Generate malloc/scratch_buffer.gl.h
if [ -f lib/malloc/scratch_buffer.h ]; then
    echo "  GEN malloc/scratch_buffer.gl.h"
    sed -e 1h -e '1s,.*,/* DO NOT EDIT! GENERATED AUTOMATICALLY! */,' -e 1G \
        -e 's|__always_inline|inline _GL_ATTRIBUTE_ALWAYS_INLINE|g' \
        -e 's|__glibc_likely|_GL_LIKELY|g' \
        -e 's|__glibc_unlikely|_GL_UNLIKELY|g' \
        -e '/libc_hidden_proto/d' \
        lib/malloc/scratch_buffer.h > lib/malloc/scratch_buffer.gl.h
else
    echo "  SKIP malloc/scratch_buffer.gl.h (source not found)"
fi

echo "Gnulib .gl.h headers generated successfully!"
