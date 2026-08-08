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
   freloc_check_fill, but ZELN-scoped.  The spike imports exactly ONE
   runtime subr (&Fmessage); index = freloc slot.  The .ll emitted by
   tools/zeln-compile loads freloc[0] and calls it with the Emacs MANY
   calling convention (Lisp_Object (*)(ptrdiff_t, Lisp_Object *)),
   matching struct Lisp_Subr's aMANY slot — so the .ll needs no extern
   shim and the main executable does not need -rdynamic: the .zeln
   reaches Fmessage purely through the loader-patched freloc pointer,
   exactly like gccjit's .eln (comp.c:5311).  */

#define ZELN_F_RELOC_MAX 64

typedef struct
{
  void *link_table[ZELN_F_RELOC_MAX];
  ptrdiff_t size;
} zeln_f_reloc_t;

static zeln_f_reloc_t zeln_freloc;

/* IDX_MESSAGE = 0 is the single imported runtime subr for the spike.
   The native fn (message "zeln-spike alive") 42 calls message once.  */
enum { IDX_MESSAGE = 0 };

static const struct
{
  const char *name;
  void *fn;
} zeln_imports[] = {
  { "message", (void *) &Fmessage },
};

static void
zeln_freloc_check_fill (void)
{
  if (zeln_freloc.size)
    return;
  eassert (countof (zeln_imports) <= ZELN_F_RELOC_MAX);
  for (ptrdiff_t i = 0; i < (ptrdiff_t) countof (zeln_imports); i++)
    zeln_freloc.link_table[i] = zeln_imports[i].fn;
  zeln_freloc.size = (ptrdiff_t) countof (zeln_imports);
}

/* ------------------------------------------------------------------ */
/* (b) ABI hash — mirror comp.c:782 hash_native_abi + comp.c:723
   comp_hash_string (MD5 -> hex -> first 8 chars), but over ZELN's own
   ABI tag + the spike's own imported subr surface.  Distinct from the
   gccjit ABI_VERSION "13" so a stale .eln hash can never collide with a
   ZELN hash and vice versa.

   Vzeln_abi_hash is NOT declared here: DEFVAR_LISP ("zeln-abi-hash",
   Vzeln_abi_hash, ...) in syms_of_compz makes make-docfile emit
   `#define Vzeln_abi_hash globals.f_Vzeln_abi_hash' into globals.h, so
   the name is globally available (via lisp.h -> globals.h) with no
   separate extern/definition (same pattern as comp.c's Vcomp_abi_hash).  */

static void
hash_zeln_abi (void)
{
  if (!NILP (Vzeln_abi_hash))
    return;

  /* Subr-signature string for the spike's imports:
       name ++ prin1 (subr-arity)        mirror comp.c:769 comp--subr-signature
     The M0 spike imports exactly one subr, `message', whose arity is
     (1 . MANY) -> prin1 -> "(1 . many)"; the composed signature is the
     fixed literal below.  (M1+ generalizes this by walking the imported
     subr list through Fsymbol_function + Fsubr_arity; Fsubr_arity takes
     the subr Lisp_Object, not the C fn ptr, so the general form belongs
     with the real importer.)  */
  Lisp_Object sig = build_string ("message(1 . many)");

  /* Key = ABI_VERSION ++ version ++ config ++ config-options ++ sig,
     mirroring comp.c:787-793.  ZELN_ABI_VERSION ("Z1") is the
     ZELN-native analogue of gccjit's ABI_VERSION ("13"); it comes from
     config.h (config_values.txt + tools/gen-config), not a #define
     here, so the spike and the gate compute it from one source.  */
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

  /* Wrap the native machine code into a freshly-allocated subr-0 so the
     caller can funcall it.  Mirrors how comp.c exposes a native fn as a
     callable Lisp_Object; M0 uses a plain C subr (gccjit uses a closure)
     because the spike has no captured lexvars.  ALLOCATE_PLAIN_PSEUDOVECTOR
     sets lisplen=0, so GC traces none of the subr's Lisp_Object slots —
     we still zero the non-header fields defensively (backtrace / doc
     lookup may read symbol_name / intspec / doc).  */
  struct Lisp_Subr *subr =
    ALLOCATE_PLAIN_PSEUDOVECTOR (struct Lisp_Subr, PVEC_SUBR);
  memclear (&subr->function,
	    sizeof (*subr) - offsetof (struct Lisp_Subr, function));
  subr->function.a0 = e->native_fn;	/* Lisp_Object (*) (void) */
  subr->min_args = 0;
  subr->max_args = 0;
  subr->symbol_name = "zeln-spike";

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
/* syms_of_compz — called from src/emacs.c under HAVE_NATIVE_COMP_ZIG.  */

void
syms_of_compz (void)
{
  DEFSYM (Qnative_lisp_file_inconsistent, "native-lisp-file-inconsistent");
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
