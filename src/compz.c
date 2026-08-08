/* Native-comp Zig path (the `.zeln` subsystem) — C side.

   Compiled ONLY when the build switch HAVE_NATIVE_COMP_ZIG is on
   (conditional addCSourceFile in build.zig).  gccjit comp.c / comp.h
   are a separate translation unit and are NEVER touched: the two paths
   are physically isolated (plan section 2).

   This file holds the four C-side pieces the M0 spike contract needs
   (plan section 5 / .omc/plans/native-comp-zig-zeln.md M0):

   (a) zeln_freloc state + zeln_freloc_check_fill  (mirror comp.c:526/824)
       importing exactly one runtime subr: &Fmessage.
   (b) hash_zeln_abi + Vzeln_abi_hash               (mirror comp.c:782/723)
       over ZELN_ABI_VERSION + version/config + "message(1 . many)".
   (c) the loader DEFUN comp-z-load-zeln:  dlopen -> dlsym "zeln_entry"
       -> verify freloc_hash_z == Vzeln_abi_hash -> patch the freloc
       link-table base -> Fread the const blob into d_reloc_z -> wrap
       native_fn into a struct Lisp_Subr -> return it.
   (d) the serializer DEFUN comp-z-write-spike-zunit: writes the
       hardcoded zunit bytes + the manifest for the ONE spike fn (runs
       in the dumped emacs; consumed by tools/zeln-compile).

   The gccjit path is not modified, not linked, not referenced.

   Copyright (C) 2026 Free Software Foundation, Inc.

   This file is part of GNU Emacs.

   GNU Emacs is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   GNU Emacs is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.  */

#include <config.h>

#include "compz.h"

#ifdef HAVE_NATIVE_COMP_ZIG

#include "dynlib.h"

/* ------------------------------------------------------------------ */
/* (a) freloc state — mirror comp.c:526 f_reloc_t / comp.c:824
   freloc_check_fill, but ZELN-scoped over the fixed M1 surface below.
   The .ll reaches every C entry point purely through the loader-patched
   freloc pointer (`base -> base[IDX_*]'), so the .zeln needs no extern
   symbol and the main executable needs no -rdynamic — exactly like
   gccjit's .eln (comp.c:5311).  */

#define ZELN_F_RELOC_MAX 64

typedef struct
{
  void *link_table[ZELN_F_RELOC_MAX];
  ptrdiff_t size;
} zeln_f_reloc_t;

static zeln_f_reloc_t zeln_freloc;

/* ------------------------------------------------------------------ */
/* M1 freloc surface — a FIXED, CLOSED set of C entry points every M1
   .zeln may call.  Each opcode the M1 emitter translates maps to a
   fixed IDX_* known to both the emitter (tools/zeln-compile) and this
   table; the manifest / ABI hash are derived from the same table, so
   there is no per-function freloc walking and no per-function ABI
   drift (plan M1 design).  Direct-call specialization is M3.

   The table holds void* fn pointers; the emitter emits a per-IDX call
   with the agreed signature (heterogeneous calling convention, uniform
   storage).  Two conventions are in use:

     - IDX_SETUP_ARGS:  Lisp_Object *(*)(ptrdiff_t, ptrdiff_t,
                            Lisp_Object *, Lisp_Object *)  -> ptr
       (the native prologue; returns the new virtual-stack `top').
     - IDX_NILP:        ptrdiff_t (*)(ptrdiff_t, Lisp_Object *) -> 0/1
       (a RAW 0/1, not a tagged Lisp_Object, so the IR can branch on
       `icmp eq i64 %ret, 0' without knowing Lisp_Object tag bits).
     - every other IDX: Lisp_Object (*)(ptrdiff_t, Lisp_Object *)
       (the uniform MANY convention matching struct Lisp_Subr aMANY).

   ZELN_ABI_VERSION was bumped Z1 -> Z2 for this layout + surface, so a
   stale M0 .zeln (whose freloc surface was just &Fmessage) is rejected
   by the hash gate before any native code runs.  */

/* Prologue helper: replicates exec_byte_code setup_frame arg binding
   (bytecode.c:535-549) into the caller-provided virtual stack.  ARGS
   is the MANY args vector the subr received; STACK is &frame_base of
   the native fn's alloca.  Returns the new `top' (deepest pushed
   value), aliasing STACK — exactly the interpreter's `top' after its
   arg-binding loop.  Mandatory/rest/nonrest are decoded from
   ARGS_TEMPLATE, which the emitter bakes in as a compile-time literal.  */
Lisp_Object *
zeln_setup_args (ptrdiff_t args_template, ptrdiff_t nargs,
		 Lisp_Object *args, Lisp_Object *stack)
{
  bool rest = (args_template & 128) != 0;
  int mandatory = args_template & 127;
  ptrdiff_t nonrest = args_template >> 8;
  if (! (mandatory <= nargs && (rest || nargs <= nonrest)))
    Fsignal (Qwrong_number_of_arguments,
	     list2 (Fcons (make_fixnum (mandatory), make_fixnum (nonrest)),
		    make_fixnum (nargs)));
  Lisp_Object *top = stack - 1;	/* mirror `top = frame_base - 1' */
  ptrdiff_t pushedargs = min (nonrest, nargs);
  for (ptrdiff_t i = 0; i < pushedargs; i++)
    *++top = args[i];		/* PUSH */
  if (nonrest < nargs)
    *++top = Flist (nargs - nonrest, args + nonrest);
  else
    for (ptrdiff_t i = nargs - rest; i < nonrest; i++)
      *++top = Qnil;
  return top;
}

/* Generic call shim for the Bcall family.  args[0] = fun (the TOP the
   interpreter reads), args[1..nargs-1] = the actuals.  funcall_general
   is the EXACT non-fast-path the interpreter's docall falls back to
   (bytecode.c:824): it does symbol resolution, closure dispatch
   (recursive exec_byte_code), funcall_subr, with full backtrace /
   debug / gc.  So a .zeln calling another closure or a subr behaves
   identically to the interpreter.  */
static Lisp_Object
zeln_funcall (ptrdiff_t nargs, Lisp_Object *args)
{
  return funcall_general (args[0], nargs - 1, args + 1);
}

/* Branch-test helper.  Returns a RAW 0/1 (NOT a tagged Lisp_Object) so
   the emitter's conditional `br' can test `icmp eq i64 %ret, 0' without
   ever computing Lisp_Object tag bits in the IR (USE_LSB_TAG never
   leaks).  The value is consumed only by the branch.  */
static ptrdiff_t
zeln_isnil (ptrdiff_t nargs, Lisp_Object *args)
{
  return NILP (args[0]) ? 1 : 0;
}

/* Per-opcode primitive shims.  Each wraps the C primitive the M1
   opcode maps to, behind the uniform MANY signature.  Calling the
   generic primitive directly (instead of the interpreter's fixnum
   inline fast path) is behaviorally identical: the fast path only
   short-circuits the common case and falls back to the SAME primitive
   on overflow / non-fixnum (bytecode.c:1331 Bplus, 1256 Beqlsign, ...).
   The differential test includes fixnum-overflow inputs to prove it.  */
static Lisp_Object zeln_plus     (ptrdiff_t n, Lisp_Object *a) { return Fplus     (n, a); }
static Lisp_Object zeln_minus    (ptrdiff_t n, Lisp_Object *a) { return Fminus    (n, a); }
static Lisp_Object zeln_times    (ptrdiff_t n, Lisp_Object *a) { return Ftimes    (n, a); }
static Lisp_Object zeln_sub1     (ptrdiff_t n, Lisp_Object *a) { return Fsub1     (a[0]); }
static Lisp_Object zeln_add1     (ptrdiff_t n, Lisp_Object *a) { return Fadd1     (a[0]); }
static Lisp_Object zeln_negate   (ptrdiff_t n, Lisp_Object *a) { return Fminus    (1, a); }
static Lisp_Object zeln_max      (ptrdiff_t n, Lisp_Object *a) { return Fmax      (n, a); }
static Lisp_Object zeln_min      (ptrdiff_t n, Lisp_Object *a) { return Fmin      (n, a); }
static Lisp_Object zeln_eqlsign  (ptrdiff_t n, Lisp_Object *a) { return Feqlsign  (n, a); }
static Lisp_Object zeln_gtr      (ptrdiff_t n, Lisp_Object *a) { return Fgtr      (n, a); }
static Lisp_Object zeln_lss      (ptrdiff_t n, Lisp_Object *a) { return Flss      (n, a); }
static Lisp_Object zeln_leq      (ptrdiff_t n, Lisp_Object *a) { return Fleq      (n, a); }
static Lisp_Object zeln_geq      (ptrdiff_t n, Lisp_Object *a) { return Fgeq      (n, a); }
static Lisp_Object zeln_equal    (ptrdiff_t n, Lisp_Object *a) { return Fequal    (a[0], a[1]); }
static Lisp_Object zeln_eq       (ptrdiff_t n, Lisp_Object *a) { return Feq       (a[0], a[1]); }
static Lisp_Object zeln_null     (ptrdiff_t n, Lisp_Object *a) { return Fnull     (a[0]); }
static Lisp_Object zeln_car      (ptrdiff_t n, Lisp_Object *a) { return Fcar      (a[0]); }
static Lisp_Object zeln_cdr      (ptrdiff_t n, Lisp_Object *a) { return Fcdr      (a[0]); }
static Lisp_Object zeln_cons     (ptrdiff_t n, Lisp_Object *a) { return Fcons     (a[0], a[1]); }
static Lisp_Object zeln_list1    (ptrdiff_t n, Lisp_Object *a) { return list1     (a[0]); }
static Lisp_Object zeln_list2    (ptrdiff_t n, Lisp_Object *a) { return list2     (a[0], a[1]); }
static Lisp_Object zeln_list3    (ptrdiff_t n, Lisp_Object *a) { return list3     (a[0], a[1], a[2]); }
static Lisp_Object zeln_list4    (ptrdiff_t n, Lisp_Object *a) { return list4     (a[0], a[1], a[2], a[3]); }
static Lisp_Object zeln_list     (ptrdiff_t n, Lisp_Object *a) { return Flist     (n, a); }
static Lisp_Object zeln_symbolp  (ptrdiff_t n, Lisp_Object *a) { return Fsymbolp  (a[0]); }
static Lisp_Object zeln_consp    (ptrdiff_t n, Lisp_Object *a) { return Fconsp    (a[0]); }
static Lisp_Object zeln_stringp  (ptrdiff_t n, Lisp_Object *a) { return Fstringp  (a[0]); }
static Lisp_Object zeln_listp    (ptrdiff_t n, Lisp_Object *a) { return Flistp    (a[0]); }
static Lisp_Object zeln_numberp  (ptrdiff_t n, Lisp_Object *a) { return Fnumberp  (a[0]); }
static Lisp_Object zeln_integerp (ptrdiff_t n, Lisp_Object *a) { return Fintegerp (a[0]); }

/* The IDX_* enum: stable indices referenced by the emitter's IR
   (`getelementptr [SURFACE x ptr], %lt, 0, IDX_*').  Order is frozen:
   adding an entry appends; never reorder (the hash fingerprints the
   ordered name list).  */
enum {
  IDX_SETUP_ARGS = 0,
  IDX_FUNCALL,
  IDX_NILP,
  IDX_PLUS,
  IDX_MINUS,
  IDX_TIMES,
  IDX_SUB1,
  IDX_ADD1,
  IDX_NEGATE,
  IDX_MAX,
  IDX_MIN,
  IDX_EQLSIGN,
  IDX_GTR,
  IDX_LSS,
  IDX_LEQ,
  IDX_GEQ,
  IDX_EQUAL,
  IDX_EQ,
  IDX_NULL,
  IDX_CAR,
  IDX_CDR,
  IDX_CONS,
  IDX_LIST1,
  IDX_LIST2,
  IDX_LIST3,
  IDX_LIST4,
  IDX_LIST,
  IDX_SYMBOLP,
  IDX_CONSP,
  IDX_STRINGP,
  IDX_LISTP,
  IDX_NUMBERP,
  IDX_INTEGERP,
  ZELN_F_RELOC_COUNT
};

static const struct
{
  const char *name;
  const char *arity;		/* prin1-style arity fingerprint token */
  void *fn;
} zeln_imports[] = {
  [IDX_SETUP_ARGS] = { "zeln-setup-args", "(0 . many)", (void *) &zeln_setup_args },
  [IDX_FUNCALL]    = { "zeln-funcall",    "(0 . many)", (void *) &zeln_funcall },
  [IDX_NILP]       = { "zeln-isnil",      "1",          (void *) &zeln_isnil },
  [IDX_PLUS]       = { "+",               "(0 . many)", (void *) &zeln_plus },
  [IDX_MINUS]      = { "-",               "(0 . many)", (void *) &zeln_minus },
  [IDX_TIMES]      = { "*",               "(0 . many)", (void *) &zeln_times },
  [IDX_SUB1]       = { "1-",              "1",          (void *) &zeln_sub1 },
  [IDX_ADD1]       = { "1+",              "1",          (void *) &zeln_add1 },
  [IDX_NEGATE]     = { "negate",          "1",          (void *) &zeln_negate },
  [IDX_MAX]        = { "max",             "(1 . many)", (void *) &zeln_max },
  [IDX_MIN]        = { "min",             "(1 . many)", (void *) &zeln_min },
  [IDX_EQLSIGN]    = { "=",               "(1 . many)", (void *) &zeln_eqlsign },
  [IDX_GTR]        = { ">",               "(1 . many)", (void *) &zeln_gtr },
  [IDX_LSS]        = { "<",               "(1 . many)", (void *) &zeln_lss },
  [IDX_LEQ]        = { "<=",              "(1 . many)", (void *) &zeln_leq },
  [IDX_GEQ]        = { ">=",              "(1 . many)", (void *) &zeln_geq },
  [IDX_EQUAL]      = { "equal",           "2",          (void *) &zeln_equal },
  [IDX_EQ]         = { "eq",              "2",          (void *) &zeln_eq },
  [IDX_NULL]       = { "null",            "1",          (void *) &zeln_null },
  [IDX_CAR]        = { "car",             "1",          (void *) &zeln_car },
  [IDX_CDR]        = { "cdr",             "1",          (void *) &zeln_cdr },
  [IDX_CONS]       = { "cons",            "2",          (void *) &zeln_cons },
  [IDX_LIST1]      = { "list1",           "1",          (void *) &zeln_list1 },
  [IDX_LIST2]      = { "list2",           "2",          (void *) &zeln_list2 },
  [IDX_LIST3]      = { "list3",           "3",          (void *) &zeln_list3 },
  [IDX_LIST4]      = { "list4",           "4",          (void *) &zeln_list4 },
  [IDX_LIST]       = { "list",            "(0 . many)", (void *) &zeln_list },
  [IDX_SYMBOLP]    = { "symbolp",         "1",          (void *) &zeln_symbolp },
  [IDX_CONSP]      = { "consp",           "1",          (void *) &zeln_consp },
  [IDX_STRINGP]    = { "stringp",         "1",          (void *) &zeln_stringp },
  [IDX_LISTP]      = { "listp",           "1",          (void *) &zeln_listp },
  [IDX_NUMBERP]    = { "numberp",         "1",          (void *) &zeln_numberp },
  [IDX_INTEGERP]   = { "integerp",        "1",          (void *) &zeln_integerp },
};

static void
zeln_freloc_check_fill (void)
{
  if (zeln_freloc.size)
    return;
  eassert (ZELN_F_RELOC_COUNT <= ZELN_F_RELOC_MAX);
  for (ptrdiff_t i = 0; i < ZELN_F_RELOC_COUNT; i++)
    {
      eassert (zeln_imports[i].fn != NULL);
      zeln_freloc.link_table[i] = zeln_imports[i].fn;
    }
  zeln_freloc.size = ZELN_F_RELOC_COUNT;
}

/* ------------------------------------------------------------------ */
/* (b) ABI hash — mirror comp.c:782 hash_native_abi + comp.c:723
   comp_hash_string (MD5 -> hex -> first 8 chars), but over ZELN's own
   ABI tag + the fixed M1 freloc surface.  Distinct from the gccjit
   ABI_VERSION "13" so a stale .eln hash can never collide with a ZELN
   hash and vice versa.

   Vzeln_abi_hash is NOT declared here: DEFVAR_LISP ("zeln-abi-hash",
   Vzeln_abi_hash, ...) in syms_of_compz makes make-docfile emit
   `#define Vzeln_abi_hash globals.f_Vzeln_abi_hash' into globals.h, so
   the name is globally available (via lisp.h -> globals.h) with no
   separate extern/definition (same pattern as comp.c's Vcomp_abi_hash).  */

/* The signature fingerprint over the ordered M1 freloc surface:
   name ++ arity per import (mirror comp.c:769 comp--subr-signature).
   Constant for ALL M1 functions; shared by the hash and the manifest
   so they cannot drift apart.  */
static Lisp_Object
zeln_signature_string (void)
{
  Lisp_Object sig = build_string ("");
  for (ptrdiff_t i = 0; i < ZELN_F_RELOC_COUNT; i++)
    sig = concat3 (sig,
		   build_string (zeln_imports[i].name),
		   build_string (zeln_imports[i].arity));
  return sig;
}

static void
hash_zeln_abi (void)
{
  if (!NILP (Vzeln_abi_hash))
    return;

  Lisp_Object sig = zeln_signature_string ();

  /* Key = ABI_VERSION ++ version ++ config ++ config-options ++ sig,
     mirroring comp.c:787-793.  ZELN_ABI_VERSION ("Z2" for M1) is the
     ZELN-native analogue of gccjit's ABI_VERSION ("13"); it comes from
     config.h (config_values.txt + tools/gen-config), not a #define
     here, so the serializer, the gate, and the Zig tool compute it from
     one source.  */
  Lisp_Object key
    = concat3 (build_string (ZELN_ABI_VERSION),
	       concat3 (Vemacs_version, Vsystem_configuration,
			Vsystem_configuration_options),
	       sig);

  /* comp_hash_string = MD5 hex digest, first 8 chars (comp.c:723).
     Use the Lisp-visible `md5' (32-char hex) via Ffuncall, then
     substring to 8 — avoids a direct md5_buffer/hexbuf_digest dep.  */
  Lisp_Object md5_args[2] = { intern_c_string ("md5"), key };
  Lisp_Object digest = Ffuncall (2, md5_args);
  Vzeln_abi_hash = Fsubstring (digest, Qnil, make_fixnum (8));
}

/* ------------------------------------------------------------------ */
/* (c) loader.  comp-z-load-zeln (FILE) -> funcallable Lisp_Object
   wrapping the .zeln's native_fn.  Mirrors comp.c load_comp_unit
   (comp.c:5232) + load_static_obj (comp.c:5163), collapsed to the
   M0 single-fn contract.  */

/* The freloc_link_table_z slot in the .zeln is a single void* the
   loader overwrites with zeln_freloc.link_table (the base).  Native
   code then dereferences base -> base[IDX_MESSAGE] -> &Fmessage.
   Mirrors comp.c:5295/5311 (*freloc_link_table = freloc.link_table).  */
static void
zeln_patch_freloc (zeln_entry_t *e)
{
  zeln_freloc_check_fill ();
  /* e->freloc_link_table_z points at the .zeln global slot; write the
     live base through it.  */
  *e->freloc_link_table_z = zeln_freloc.link_table;
}

/* Fread the const blob (a vector in read-syntax) and scatter it into
   e->d_reloc_z[0..n_d_reloc).  Mirrors comp.c:5318+5322
   (comp_u->data_vec = load_static_obj (...); data_relocs[i] = AREF).  */
static void
zeln_fill_d_reloc (zeln_entry_t *e)
{
  zeln_static_obj_t *blob = e->d_reloc_blob;
  eassert (blob);
  /* Fread the read-syntax vector.  The spike blob is plain
     `["zeln-spike alive" 42]' with no #$ placeholder, so load-file-name
     need not be bound (comp.c:5173 binds it for #$ substitution only).  */
  Lisp_Object vec = Fread (make_string (blob->data, blob->len));
  eassert (VECTORP (vec));
  ptrdiff_t n = XFIXNUM (Flength (vec));
  eassert (n == e->n_d_reloc);
  for (ptrdiff_t i = 0; i < n; i++)
    e->d_reloc_z[i] = AREF (vec, i);
}

/* Verify the .zeln's baked ABI hash matches the running emacs's
   Vzeln_abi_hash.  Mirror comp.c:5303-5305 (LINK_TABLE_HASH_SYM gate).  */
static void
zeln_verify_hash (zeln_entry_t *e)
{
  Lisp_Object file_hash = make_string (e->freloc_hash_z, 8);
  if (NILP (Fstring_equal (file_hash, Vzeln_abi_hash)))
    xsignal1 (Qnative_lisp_file_inconsistent,
	      make_string (e->freloc_hash_z, 8));
}

DEFUN ("comp-z-load-zeln", Fcomp_z_load_zeln, Scomp_z_load_zeln, 1, 1, 0,
       doc: /* Load a .zeln native-comp unit (Zig path) and return its entry fn.
FILE is the .zeln path.  M0 spike: the unit holds one 0-arg fn whose
native body is `(message "zeln-spike alive") 42'.  The returned value is
a subr wrapping the .zeln's native_fn; funcall it to run the native code.
For internal use.  */)
  (Lisp_Object file)
{
  CHECK_STRING (file);
  /* M0 is glibc-Linux only; ASCII paths need no file-name encoding, so
     dynlib_open gets the raw SSDATA bytes.  (ENCODE_FILE is a no-op on
     POSIX but is conditionally defined in lisp.h; SSDATA is sufficient
     and always available.)  */
  dynlib_handle_ptr handle = dynlib_open (SSDATA (file));
  if (!handle)
    xsignal1 (Qnative_lisp_file_inconsistent,
	      build_string (dynlib_error () ? dynlib_error ()
					    : "dynlib_open failed"));

  zeln_entry_t *(*entry_sym) (void) =
    (zeln_entry_t * (*) (void)) dynlib_sym (handle, "zeln_entry");
  if (!entry_sym)
    xsignal1 (Qnative_lisp_file_inconsistent,
	      build_string ("no zeln_entry symbol"));

  zeln_entry_t *e = entry_sym ();
  eassert (e);

  /* Order mirrors comp.c load_comp_unit: hash gate, then patch relocs,
     then reconstruct data.  The hash gate fires first so a stale-ABI
     .zeln is rejected before any native code can run.  */
  hash_zeln_abi ();
  zeln_verify_hash (e);
  zeln_patch_freloc (e);
  zeln_fill_d_reloc (e);

  /* Wrap the native machine code into a freshly-allocated MANY subr so
     the caller can funcall it.  M1 native fns use the MANY convention
     (i64 (i64 nargs, ptr args)) matching the aMANY slot (lisp.h:2188);
     the M0 spike's @zeln_spike_native was moved to the same convention
     so one loader path serves both.  funcall_subr dispatches aMANY when
     max_args == MANY (eval.c:3301), passing the raw (nargs, args) — the
     native fn's prologue (zeln_setup_args) is the real arity enforcer
     (it bakes args_template and signals wrong_number_of_arguments), so
     min=0/max=MANY here is correct without embedding arity in the entry
     struct (which stays field-for-field identical to M0).  Mirrors how
     comp.c exposes a native fn as a callable Lisp_Object; we use a
     plain C subr (gccjit uses a closure) because M1 closures carry no
     captured lexvars across the C<->Zig boundary (constants live in
     d_reloc_z).  ALLOCATE_PLAIN_PSEUDOVECTOR sets lisplen=0, so GC
     traces none of the subr's Lisp_Object slots — we still zero the
     non-header fields defensively (backtrace / doc lookup may read
     symbol_name / intspec / doc).  */
  struct Lisp_Subr *subr =
    ALLOCATE_PLAIN_PSEUDOVECTOR (struct Lisp_Subr, PVEC_SUBR);
  memclear (&subr->function,
	    sizeof (*subr) - offsetof (struct Lisp_Subr, function));
  subr->function.aMANY = e->native_fn;
  subr->min_args = 0;
  subr->max_args = MANY;
  subr->symbol_name = "zeln-native";

  Lisp_Object subr_obj;
  XSETSUBR (subr_obj, subr);
  return subr_obj;
}

/* ------------------------------------------------------------------ */
/* (d) serializer.  comp-z-write-spike-zunit writes the hardcoded zunit
   for the ONE spike fn + the manifest.  Runs in the dumped emacs; the
   build step shells out to it, then runs tools/zeln-compile over the
   .zunit.  See the M0 zunit format in the plan/design.  */

#define ZUNIT_MAGIC 0x5A554E54u	/* "ZUNT", validated by tools/zeln-compile */

static void
emit_u32 (FILE *f, uint32_t v)
{
  unsigned char bytes[4] = { v & 0xFF, (v >> 8) & 0xFF,
			     (v >> 16) & 0xFF, (v >> 24) & 0xFF };
  fwrite (bytes, 1, 4, f);
}

static void
emit_u16 (FILE *f, uint16_t v)
{
  unsigned char bytes[2] = { v & 0xFF, (v >> 8) & 0xFF };
  fwrite (bytes, 1, 2, f);
}

static void
emit_u8 (FILE *f, uint8_t v)
{
  unsigned char b = v;
  fwrite (&b, 1, 1, f);
}

static void
emit_bytes (FILE *f, const char *p, ptrdiff_t len)
{
  fwrite (p, 1, len, f);
}

DEFUN ("comp-z-write-spike-zunit", Fcomp_z_write_spike_zunit,
       Scomp_z_write_spike_zunit, 1, 1, 0,
       doc: /* Write the M0 spike zunit + manifest for the .zeln pipeline.
OUT-PREFIX is the output path with no suffix; this writes
<OUT-PREFIX>.zunit and <OUT-PREFIX>.manifest.  The zunit is the
hardcoded serialization of the single spike fn; the manifest carries
the ZELN ABI tag, the imported-subr signature, and the 8-hex ABI hash
that tools/zeln-compile bakes into the .zeln.  For internal use.  */)
  (Lisp_Object out_prefix)
{
  CHECK_STRING (out_prefix);
  hash_zeln_abi ();
  eassert (!NILP (Vzeln_abi_hash));

  /* Build the C-string prefix (M0: ASCII build paths only).  */
  char prefix[4096];
  ptrdiff_t plen = SBYTES (out_prefix);
  if (plen >= (ptrdiff_t) sizeof (prefix) - 16)
    error ("comp-z-write-spike-zunit: prefix too long");
  memcpy (prefix, SSDATA (out_prefix), plen);
  prefix[plen] = '\0';

  /* --- .zunit: header + opcodes + constants (all LE, packed).  */
  char path[4096 + 16];
  snprintf (path, sizeof path, "%s.zunit", prefix);
  FILE *zout = emacs_fopen (path, "wb");
  if (!zout)
    report_file_error ("Opening zunit", build_string (path));

  emit_u32 (zout, ZUNIT_MAGIC);
  emit_u8  (zout, 1);		/* zabi_version = ZELN_SPIKE_ABI == 1 */
  emit_u8  (zout, 0);		/* arity_min: no required args */
  emit_u8  (zout, 0);		/* arity_max: 0 => (0 . 0) no-arg fn */
  emit_u8  (zout, 2);		/* stack_depth: doc only at M0 */

  /* Opcodes (format-parity only; the M0 Tier-0 emitter ignores them):
     push-const(0) Bcall1 push-const(1) Breturn, with Bcall1=0x41 and
     Breturn=0x87.  */
  static const char opcodes[] = { 0x00, 0x41, 0x01, 0x87 };
  emit_u16 (zout, (uint16_t) sizeof (opcodes));
  emit_bytes (zout, opcodes, sizeof (opcodes));

  /* nconsts = 2.  */
  emit_u8 (zout, 2);

  /* const[0]: tag=3 (string), read-syntax `"zeln-spike alive"' (the
     data field carries the read-syntax form, including the surrounding
     double-quotes; the loader Freads it back).  */
  static const char c0[] = "\"zeln-spike alive\"";
  emit_u8  (zout, 3);		/* tag = string */
  emit_u32 (zout, (uint32_t) (sizeof (c0) - 1));
  emit_bytes (zout, c0, sizeof (c0) - 1);

  /* const[1]: tag=1 (fixnum), read-syntax `42'.  */
  static const char c1[] = "42";
  emit_u8  (zout, 1);		/* tag = fixnum */
  emit_u32 (zout, (uint32_t) (sizeof (c1) - 1));
  emit_bytes (zout, c1, sizeof (c1) - 1);

  if (emacs_fclose (zout) != 0)
    report_file_error ("Closing zunit", build_string (path));

  /* --- .manifest: ASCII `Z1\n<sig>\n<8-hex>\n'.  */
  snprintf (path, sizeof path, "%s.manifest", prefix);
  FILE *mout = emacs_fopen (path, "w");
  if (!mout)
    report_file_error ("Opening manifest", build_string (path));

  /* Sig line: the imported subr surface, name ++ prin1(arity).  The
     spike imports only `message' (arity (1 . MANY)) -> "message(1 . many)".  */
  fprintf (mout, "%s\n", ZELN_ABI_VERSION);
  fprintf (mout, "message(1 . many)\n");
  fprintf (mout, "%s\n", SSDATA (Vzeln_abi_hash));
  emacs_fclose (mout);

  return Qt;
}

/* ------------------------------------------------------------------ */
/* (d-m1) serializer.  comp-z-write-zunit (FUNCTION OUT-PREFIX): takes
   a REAL compiled closure and writes the M1 zunit + manifest.  Extracts
   bytestr / constants / maxdepth / args_template via the same CLOSURE_
   slots the interpreter itself reads (exec_byte_code, bytecode.c:494-
   549).  The opcodes field is the raw bytestr — the EXACT bytes the C
   VM runs, copied verbatim; the emitter decodes them at compile time.  */

/* Forward-compat advisory tag for a constant (0=nil, 1=fixnum, 2=symbol,
   3=string, 4=other).  The LOADER IGNORES IT (read-syntax is the source
   of truth, exactly like M0's blob); kept only so a future reader can
   short-circuit on type without Fread.  */
static uint8_t
zeln_const_tag (Lisp_Object c)
{
  if (NILP (c))		return 0;
  if (FIXNUMP (c))	return 1;
  if (SYMBOLP (c))	return 2;
  if (STRINGP (c))	return 3;
  return 4;
}

DEFUN ("comp-z-write-zunit", Fcomp_z_write_zunit, Scomp_z_write_zunit,
       2, 2, 0,
       doc: /* Write the M1 zunit + manifest for compiled closure FUNCTION.
FUNCTION must be a lexical byte-compiled closure (CLOSUREP with a
fixnum args-template in slot 0) — the exact shape `exec_byte_code'
consumes.  Interpreted functions, &rest-only lambdas, and subrs are
rejected (out of M1 scope).  OUT-PREFIX is the output path with no
suffix; this writes <OUT-PREFIX>.zunit and <OUT-PREFIX>.manifest.
For internal use.  */)
  (Lisp_Object fun, Lisp_Object out_prefix)
{
  /* INPUT VALIDATION: CLOSUREP (PVEC_COMPILED) AND a fixnum args-template
     (a lexical closure; slot 0 holds args_template — lisp.h:3208).  This
     is the exact shape exec_byte_code consumes (bytecode.c:494-505,
     531-549).  Reject everything else (interpreted functions, &rest-only
     lambdas, subrs) with wrong-type-argument.  */
  CHECK_TYPE (CLOSUREP (fun), Qcompiled_function_p, fun);
  CHECK_STRING (out_prefix);
  CHECK_TYPE (FIXNUMP (AREF (fun, CLOSURE_ARGLIST)),
	      Qcompiled_function_p, fun);

  /* EXTRACT via the CLOSURE_ slots the interpreter uses.  */
  Lisp_Object bytestr   = AREF (fun, CLOSURE_CODE);	/* slot 1 */
  Lisp_Object vector    = AREF (fun, CLOSURE_CONSTANTS);	/* slot 2 */
  Lisp_Object maxdepth  = AREF (fun, CLOSURE_STACK_DEPTH);	/* slot 3 */
  ptrdiff_t args_tmpl   = XFIXNUM (AREF (fun, CLOSURE_ARGLIST)); /* slot 0 */
  CHECK_TYPE (STRINGP (bytestr), Qstringp, bytestr);
  CHECK_TYPE (VECTORP (vector), Qvectorp, vector);
  CHECK_TYPE (FIXNATP (maxdepth), Qwholenump, maxdepth);

  ptrdiff_t opcode_len = SBYTES (bytestr);
  ptrdiff_t nconsts    = ASIZE (vector);
  if (opcode_len > 0xFFFFFFFFu || nconsts > 0xFFFFFFFFu)
    error ("comp-z-write-zunit: bytecode/constants too large");

  hash_zeln_abi ();
  eassert (!NILP (Vzeln_abi_hash));

  char prefix[4096];
  ptrdiff_t plen = SBYTES (out_prefix);
  if (plen >= (ptrdiff_t) sizeof (prefix) - 16)
    error ("comp-z-write-zunit: prefix too long");
  memcpy (prefix, SSDATA (out_prefix), plen);
  prefix[plen] = '\0';

  /* --- .zunit (M1, zabi=2): u32 magic; u8 zabi=2; u32 args_template;
     u16 stack_depth; u32 opcode_len; u8 opcodes[opcode_len]; u32 nconsts;
     then nconsts × { u8 tag_advisory; u32 len; u8 read_syntax[len] }.  */
  char path[4096 + 16];
  snprintf (path, sizeof path, "%s.zunit", prefix);
  FILE *zout = emacs_fopen (path, "wb");
  if (!zout)
    report_file_error ("Opening zunit", build_string (path));

  emit_u32 (zout, ZUNIT_MAGIC);
  emit_u8  (zout, 2);				/* zabi_version (M1) */
  emit_u32 (zout, (uint32_t) args_tmpl);	/* 15-bit args_template */
  emit_u16 (zout, (uint16_t) XFIXNAT (maxdepth));
  emit_u32 (zout, (uint32_t) opcode_len);
  emit_bytes (zout, SSDATA (bytestr), opcode_len);	/* raw opcodes */
  emit_u32 (zout, (uint32_t) nconsts);

  /* Each constant serialized Lisp-aware via Fprin1_to_string (print.c:795)
     → its read-syntax bytes; the loader Freads them back (M0 mechanism,
     just N≥2).  */
  for (ptrdiff_t i = 0; i < nconsts; i++)
    {
      Lisp_Object c = AREF (vector, i);
      Lisp_Object printed = Fprin1_to_string (c, Qnil, Qnil);
      ptrdiff_t clen = SBYTES (printed);
      if (clen > 0xFFFFFFFFu)
	error ("comp-z-write-zunit: constant read-syntax too large");
      emit_u8  (zout, zeln_const_tag (c));	/* advisory; loader ignores */
      emit_u32 (zout, (uint32_t) clen);
      emit_bytes (zout, SSDATA (printed), clen);
    }

  if (emacs_fclose (zout) != 0)
    report_file_error ("Closing zunit", build_string (path));

  /* --- .manifest: `<ZELN_ABI_VERSION>\n<sig>\n<8-hex>\n'.  The sig line
     is the fixed M1 surface (constant for all fns); the 8-hex is what
     the Zig tool bakes into the .zeln as freloc_hash_z.  */
  snprintf (path, sizeof path, "%s.manifest", prefix);
  FILE *mout = emacs_fopen (path, "w");
  if (!mout)
    report_file_error ("Opening manifest", build_string (path));
  fprintf (mout, "%s\n", ZELN_ABI_VERSION);
  fprintf (mout, "%s\n", SSDATA (zeln_signature_string ()));
  fprintf (mout, "%s\n", SSDATA (Vzeln_abi_hash));
  emacs_fclose (mout);

  return Qt;
}

/* ------------------------------------------------------------------ */
/* syms_of_compz — called from src/emacs.c under HAVE_NATIVE_COMP_ZIG.  */

void
syms_of_compz (void)
{
  DEFSYM (Qnative_lisp_file_inconsistent, "native-lisp-file-inconsistent");
  DEFSYM (Qcompiled_function_p, "compiled-function-p");
  /* Make it a proper error condition so condition-case can match it.
     comp.c:5706-5709 does this under HAVE_NATIVE_COMP (off here), so the
     ZELN path sets it up itself: inherits from `error' (a minimal
     condition hierarchy is sufficient for M0; gccjit's chain via
     native-lisp-load-failed is not needed for the spike).  */
  Fput (Qnative_lisp_file_inconsistent, Qerror_conditions,
	list2 (Qnative_lisp_file_inconsistent, Qerror));
  Fput (Qnative_lisp_file_inconsistent, Qerror_message,
	build_string ("zeln file inconsistent with current runtime "
		      "configuration (ZELN ABI mismatch)"));

  DEFVAR_LISP ("zeln-abi-hash", Vzeln_abi_hash,
	       doc: /* ABI hash for the Zig native-comp (.zeln) path.
Computed once by `hash_zeln_abi' from ZELN_ABI_VERSION + the build
identity + the imported-subr surface.  Each loaded .zeln bakes the same
hash; mismatch on load signals `native-lisp-file-inconsistent'.  */);
  Vzeln_abi_hash = Qnil;

  defsubr (&Scomp_z_load_zeln);
  defsubr (&Scomp_z_write_spike_zunit);
  defsubr (&Scomp_z_write_zunit);

  /* Fill the freloc table early (pure pointer copy, no Lisp): the .zeln
     loader needs it.  Do NOT call hash_zeln_abi here: it builds the hash
     via Ffuncall("md5",...), and syms_of_compz runs during the bootstrap
     dump BEFORE coding systems exist (md5 signals "Invalid coding system:
     raw-text").  hash_zeln_abi is lazy: computed on first .zeln load
     (zeln_verify_hash) or serialize (comp-z-write-spike-zunit), both of
     which run post-dump where coding systems are available.  */
  zeln_freloc_check_fill ();
}

#else /* !HAVE_NATIVE_COMP_ZIG */

/* Off-path stub so emacs.c always has a syms_of_compz to call.  When the
   switch is off, compz.c is not even compiled (build.zig gates it), but
   the header declares syms_of_compz conditionally; keep this defensive
   no-op in case the file is ever compiled without the macro.  */
void
syms_of_compz (void)
{
}

#endif /* HAVE_NATIVE_COMP_ZIG */
