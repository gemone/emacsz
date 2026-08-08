/* Native-comp Zig path definitions (the `.zeln` subsystem).

This header is the C-facing contract for the HAVE_NATIVE_COMP_ZIG path
(tools/zeln-compile + src/compz.c).  It declares the entry struct the
.zeln exports, the loader-side state, and syms_of_compz.  comp.c /
comp.h (the gccjit path) are completely untouched; the two paths are
physically isolated (plan section 2).

Compiled ONLY when the build switch HAVE_NATIVE_COMP_ZIG is on
(addCSourceFile in build.zig, gated by -Dnative-comp-zig).  */

#ifndef COMPZ_H
#define COMPZ_H

/* zeln_entry_t / zeln_entry are referenced by src/compz.c only (the
   loader), which itself is compiled exclusively under
   HAVE_NATIVE_COMP_ZIG, so the whole contract lives under the guard.  */
#ifdef HAVE_NATIVE_COMP_ZIG

#include <config.h>
#include "lisp.h"

/* A serialized read-syntax blob: { len, data[] }.  Mirrors comp.c:664
   static_obj_t (the same shape load_static_obj Freads back via
   Fread (make_string (blob->data, blob->len))).  */
typedef struct
{
  ptrdiff_t len;
  char data[];
} zeln_static_obj_t;

/* Returned by the exported zeln_entry() symbol.  All slots are
   .zeln-static until the loader (compz.c Fcomp_z_load_zeln) patches /
   writes them.  Mirrors the per-symbol reloc slots comp.c looks up at
   comp.c:5241-5311, collapsed into ONE struct for the M0 single-fn
   spike (plan section 5.3).  The LLVM-IR struct emitted by
   tools/zeln-compile MUST match this layout field-for-field (offsets are
   all 8-byte aligned on x86-64, so there is no padding to negotiate).  */
typedef struct
{
  /* The actual machine code: @zeln_spike_native.  Emacs subr-0 shape
     (no args); the loader wraps it into a struct Lisp_Subr on load.
     Returning Lisp_Object (an EMACS_INT / i64 in the IR).  */
  Lisp_Object (*native_fn) (void);

  /* &@freloc_link_table_z_slot: the loader writes the live
     zeln_freloc.link_table base address into this slot (mirrors
     comp.c:5295 *freloc_link_table = freloc.link_table).  Native code
     then dereferences slot -> base -> &Fmessage.  The slot itself is a
     single void* (the base); the indirection through this field lets
     M1 generalize to a real multi-entry link table without changing
     the entry contract.  */
  void **freloc_link_table_z;

  /* &@freloc_hash_z: a NUL-terminated 8-hex ABI-hash string, baked into
     the .zeln by Zig from the manifest (plan section 5.2).  The loader
     Fstring_equal-compares it against Vzeln_abi_hash and rejects on
     mismatch (mirrors comp.c:5303-5305 over LINK_TABLE_HASH_SYM).  */
  const char *freloc_hash_z;

  /* &@d_reloc_z[0]: the loader Freads the const blob and writes
     d_reloc_z[0] = the string "zeln-spike alive", d_reloc_z[1] =
     make_fixnum (42).  The native fn reads these slots; the .ll never
     computes Lisp_Object tag bits.  */
  Lisp_Object *d_reloc_z;

  /* == nconsts == 2 for the spike.  */
  ptrdiff_t n_d_reloc;

  /* &@d_reloc_z_blob: the read-syntax blob (a vector) the loader Freads
     once and splits into d_reloc_z[0..n_d_reloc).  Pointed at by the
     entry struct so the loader needs no second dlsym beyond zeln_entry
     (an M0 simplification; mirrors comp.c load_static_obj (DATA_RELOC_SYM)
     but reached through the single entry handle).  */
  zeln_static_obj_t *d_reloc_blob;
} zeln_entry_t;

/* The exported entry: a .zeln-global function returning &zeln_entry_global
   (a file-static in the .zeln).  Loader resolves it via
   dynlib_sym (handle, "zeln_entry").  */
zeln_entry_t *zeln_entry (void);

/* Vzeln_abi_hash is NOT declared here: DEFVAR_LISP in compz.c makes
   make-docfile emit `#define Vzeln_abi_hash globals.f_Vzeln_abi_hash'
   into globals.h, so the name is globally available with no separate
   extern (same pattern as comp.c's Vcomp_abi_hash).  */

/* Defined in compz.c; called from src/emacs.c under
   #ifdef HAVE_NATIVE_COMP_ZIG.  */
extern void syms_of_compz (void);

#endif /* HAVE_NATIVE_COMP_ZIG */

#endif /* COMPZ_H */
