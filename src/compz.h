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

/* M2b multi-function container (zabi=3).  A .zeln now carries N native
   functions (one per defun in the source .elc) PLUS the .elc's non-defun
   top-level forms as a read-syntax blob, so loading ONE .zeln is a
   faithful mirror of loading the whole .elc (defun-fset + top-level
   replay), exactly like gccjit's .eln (comp.c load_comp_unit +
   Fnative_elisp_load).  The M0 spike and M1 single-fn .zeln are now
   simply the N=1 case of this container (empty top_level_blob), so the
   loader has ONE entry layout for all .zeln.  The LLVM-IR struct types
   emitted by tools/zeln-compile MUST match these layouts field-for-field
   (every field is 8-byte aligned on x86-64, so there is no padding).  */

/* One entry in the function table.  All slots are .zeln-static until the
   loader patches/writes them.  native_fn is the MANY-convention machine
   code; the loader wraps it into a struct Lisp_Subr and Ffsets it under
   intern(symbol_name).  d_reloc/d_reloc_blob are this fn's OWN constants
   (each closure has its own const vector); the loader Freads the blob
   once and scatters it into d_reloc[0..n_d_reloc).  Mirrors the
   per-symbol reloc slots comp.c looks up at comp.c:5241-5311.  */
typedef struct
{
  /* The native machine code: i64 (i64 nargs, ptr args), matching struct
     Lisp_Subr's aMANY slot (lisp.h:2188).  */
  Lisp_Object (*native_fn) (ptrdiff_t, Lisp_Object *);

  /* The fn's args_template (15-bit lexical-arity encoding).  Embedded
     here for reference; the native fn's prologue (zeln_setup_args) is
     the real arity enforcer, so the loader sets subr min=0/max=MANY.  */
  ptrdiff_t args_template;

  /* &@sym_name_<i>: NUL-terminated C string, the defun symbol name.  The
     loader interns it and Ffsets the native subr under it.  */
  const char *symbol_name;

  /* &@d_reloc_z_<i>[0]: the loader Freads d_reloc_blob and writes the
     live Lisp_Object constants here.  The native fn reads these slots;
     the .ll never computes Lisp_Object tag bits.  */
  Lisp_Object *d_reloc;

  /* == nconsts for this fn.  */
  ptrdiff_t n_d_reloc;

  /* &@d_reloc_blob_<i>: this fn's read-syntax const vector blob ({ len,
     data[] }).  Loader Freads it once.  */
  zeln_static_obj_t *d_reloc_blob;
} zeln_fn_entry_t;

/* The file-level entry returned by the exported zeln_entry() symbol.
   freloc_link_table_z / freloc_hash_z are shared across all fns in the
   file (the freloc surface is global; plan section 5.2).  top_level_blob
   is the .elc's non-defun top-level forms as a (progn ...) read-syntax
   blob; the loader Freads + Fevals it under the load-file-name /
   load-history Fload already bound.  */
typedef struct
{
  /* &@freloc_link_table_z: the loader writes the live
     zeln_freloc.link_table base into this slot (mirrors comp.c:5295
     *freloc_link_table = freloc.link_table).  Native code dereferences
     *slot -> base -> base[IDX_*].  */
  void **freloc_link_table_z;

  /* &@freloc_hash_z: NUL-terminated 8-hex ABI-hash string baked into the
     .zeln by Zig.  The loader Fstring_equal-compares it against
     Vzeln_abi_hash and rejects on mismatch (mirrors comp.c:5303-5305).  */
  const char *freloc_hash_z;

  /* Function-table count (1 for the M0 spike / M1 zeln-diff .zeln).  */
  ptrdiff_t n_fns;

  /* &@zeln_fn_table: the [n_fns]-element function table.  */
  zeln_fn_entry_t *fns;

  /* &@top_level_blob: { len, data[] } read-syntax of (progn ...) of the
     .elc's non-defun top-level forms; zero-len for the M0/M1 single-fn
     .zeln (no top-level replay needed).  */
  zeln_static_obj_t *top_level_blob;

  /* ---- FDO / auto profile-guided recompilation (Z5).  All three are
     emitted by every .zeln (entry-struct layout is fixed); only the
     per-fn counter BRANCH in the native code is conditional
     (`--final` drops it).  The loader uses these to auto-collect call
     counts and recompile the unit without any build-pipeline
     dependency.  ----
     &@zeln_fdo_active: the gating flag.  0 = counters disabled (the
     fn prologue's load+icmp+branch falls through, ~2 cycles/call).
     The loader writes 1 here to start collecting (set when
     zeln_auto_fdo_profile is non-nil at load).  */
  uint64_t *fdo_active;

  /* &@zeln_fdo_counters[0]: the [n_fns] per-fn call-count array.  The
     loader reads it at flush time (interval-gated, post-GC) and writes
     the profile file; the recompiled unit starts fresh zeros.  */
  uint64_t *fdo_counters;

  /* &@zeln_fdo_fallbacks[0]: the [n_fns] per-fn FALLBACK-count array —
     how many times each fn's M3 inline fast-path branches took the
     freloc fallback (bignum/float/non-fixnum).  Incremented by the
     same gated counter mechanism as fdo_counters.  The profile file
     format is `fnname<TAB>calls[<TAB>fallbacks]`, and the PGO
     recompile derives the !prof branch weights from the REAL
     calls-vs-fallbacks ratio (fixes the hardcoded 1000000:1 weights
     being wrong on overflow-heavy workloads).  Z6.  */
  uint64_t *fdo_fallbacks;

  /* == n_fns.  */
  ptrdiff_t n_fdo;

  /* &@zeln_zunit_blob: { len, data[] } — the ORIGINAL zunit bytes,
     embedded so the loader can recompile the unit at runtime: it
     writes the blob back to disk + a manifest + the profile, then
     spawns zeln-compile.  Self-contained: no .elc/.elc access needed.  */
  zeln_static_obj_t *zunit_blob;
} zeln_entry_t;

/* The exported entry: a .zeln-global function returning &zeln_entry_global
   (a file-static in the .zeln).  Loader resolves it via
   dynlib_sym (handle, "zeln_entry").  */
zeln_entry_t *zeln_entry (void);

/* Vzeln_abi_hash / Vnative_comp_zeln_load_path / Vcomp_z_native_version_dir /
   Vzeln_to_el_h are NOT declared here: DEFVAR_LISP in compz.c makes
   make-docfile emit `#define <name> globals.f_<name>' into globals.h, so
   each name is globally available with no separate extern (same pattern
   as comp.c's Vcomp_abi_hash / Vnative_comp_eln_load_path).  compz.c is
   fed to make-docfile only when -Dnative-comp-zig=true (build.zig:435),
   so the slots materialize exactly when the code referencing them is
   compiled (src/lread.c gates every reference under
   HAVE_NATIVE_COMP_ZIG).  */

/* M1 serializer: extracts bytecode + constants + stack-depth +
   args_template from a real compiled closure and writes the M1 zunit +
   manifest.  Defined in compz.c.  */
extern Lisp_Object Fcomp_z_write_zunit (Lisp_Object fun, Lisp_Object out_prefix);

/* M2b file-level serializer: loads a .elc, walks its defun closures +
   collects its non-defun top-level forms (via a load-read-function
   capture), and writes ONE zabi=3 multi-function zunit + the manifest
   (plan M2b deliverable 1).  Defined in compz.c.  */
extern Lisp_Object Fcomp_z_write_file_zunit (Lisp_Object file,
					     Lisp_Object out_prefix);

/* M1.5 cache layout.  Self-contained mirror of comp.c's
   Fcomp_el_to_eln_rel_filename (comp.c:4306) — it CANNOT reuse the gccjit
   helper, whose whole definition lives under #ifdef HAVE_NATIVE_COMP and
   is therefore invisible in the M1.5 config (gccjit OFF).  Returns the
   .zeln rel-filename for SRC_NAME (an .el / .el.gz source path):
   `<basename>-<path_hash>-<content_hash>.zeln', path/content hashes
   computed via the Ffuncall ("md5",...) trick (no md5.h/zlib dep).
   Called by src/lread.c maybe_swap_for_zeln to LOCATE the .zeln; the
   same call computes the name when PLACING the .zeln, so serialize-side
   and load-side agree by construction.  */
extern Lisp_Object Fcomp_z_el_to_zeln_rel_filename (Lisp_Object src_name);

/* M1.5: lazily build Vcomp_z_native_version_dir from Vzeln_abi_hash
   (mirror comp.c:795-821 building Vcomp_native_version_dir from
   Vcomp_abi_hash).  Distinct from the gccjit version-dir so a .zeln and
   a .eln for the same source can never collide on disk even if both
   caches pointed at the same root.  Idempotent.  Called from
   src/lread.c maybe_swap_for_zeln and src/emacs.c's load-path fixup.  */
extern void compute_z_version_dir (void);

/* Defined in compz.c; called from src/emacs.c under
   #ifdef HAVE_NATIVE_COMP_ZIG.  */
extern void syms_of_compz (void);

/* FDO: the post-GC auto profile-flush / recompile / hot-swap check.
   Called from garbage_collect (src/alloc.c) after the sweep, under
   #ifdef HAVE_NATIVE_COMP_ZIG.  No-op when zeln-auto-fdo-path is nil
   or no FDO-enabled .zeln unit is loaded.  */
extern void zeln_fdo_gc_check (void);

#endif /* HAVE_NATIVE_COMP_ZIG */

#endif /* COMPZ_H */
