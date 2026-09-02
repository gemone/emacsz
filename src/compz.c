/* Native-comp Zig path (the `.zeln` subsystem) — C side.

   Compiled ONLY when the build switch HAVE_NATIVE_COMP_ZIG is on
   (conditional addCSourceFile in build.zig).  gccjit comp.c / comp.h
   are a separate translation unit and are NEVER touched: the two paths
   are physically isolated (plan section 2).

   This file holds the four C-side pieces the M0 spike contract needs
   (plan section 5 / M0):

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
#include <sys/resource.h>

#include "compz.h"
#include "md5.h"

#ifdef HAVE_NATIVE_COMP_ZIG

#include <stdlib.h>		/* realpath, intptr_t */
#include <inttypes.h>		/* PRIu64 (FDO profile format) */
#include <timespec.h>		/* current_timespec, timespectod (FDO) */
#include "dynlib.h"
#include "sysstdio.h"		/* FILE, fseeko, ftello, fread, rewind */
#include "coding.h"		/* ENCODE_FILE / DECODE_FILE */
#include "buffer.h"		/* record_unwind_current_buffer + buffer primitives */
#include <epaths.h>		/* PATH_DUMPLOADSEARCH / PATH_REL_LOADSEARCH */

/* ------------------------------------------------------------------ */
/* (a) freloc state — mirror comp.c:526 f_reloc_t / comp.c:824
   freloc_check_fill, but ZELN-scoped over the fixed M1 surface below.
   The .ll reaches every C entry point purely through the loader-patched
   freloc pointer (`base -> base[IDX_*]'), so the .zeln needs no extern
   symbol and the main executable needs no -rdynamic — exactly like
   gccjit's .eln (comp.c:5311).  */

#define ZELN_F_RELOC_MAX 128

/* Defined after the JIT cache; the hot-call shim below needs only this
   validated lookup.  Keeping the hot path out of the generic funcall
   shim lets a compiled closure call another already-compiled closure
   without re-resolving symbols or rediscovering the closure ABI.  */
typedef Lisp_Object (*zeln_jit_entry_t) (ptrdiff_t, Lisp_Object *);
static zeln_jit_entry_t zeln_jit_validated_entry (Lisp_Object fun,
						  Lisp_Object bytestr);
static uintmax_t zeln_jit_fast_calls;

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
     - IDX_SWITCH_TARGET: ptrdiff_t (*)(ptrdiff_t, Lisp_Object *) ->
       the Bswitch target bytecode offset, or -1 for a miss (RAW, same
       rationale as IDX_NILP; the native side dispatches on the offset
       with a static switch whose case set comes from the zunit's
       switch-table sidecar).
     - every other IDX: Lisp_Object (*)(ptrdiff_t, Lisp_Object *)
       (the uniform MANY convention matching struct Lisp_Subr aMANY).

   ZELN_ABI_VERSION was bumped Z1 -> Z2 for the M1 layout + surface,
   then Z2 -> Z3 for the M2 freloc-surface growth, then Z3 -> Z4 for the
   M2b multi-function .zeln container (the entry struct gained a
   function table + top_level_blob), then Z6 -> Z7 for the Bswitch
   support (the freloc surface gained zeln-switch-target and the zunit
   format became zabi=4 with the switch-table sidecar), then
   Z7 -> Z8 to give generated Bcall sites the interpreter's complete
   call boundary (Ffuncall: quit/depth/backtrace/debug/GC), so a stale
   .zeln is rejected by the hash gate before any native code runs.  The
   IDX_* freloc surface growth is append-only (the hash fingerprints
   the ordered name list, so appending is safe but reordering is not),
   so the differential gate's per-opcode contract still holds.  */

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
   interpreter reads), args[1..nargs-1] = the actuals.

   Important: funcall_general alone is NOT the interpreter's Bcall
   boundary.  The bytecode interpreter wraps dispatch with maybe_quit,
   lisp_eval_depth, record_in_backtrace, maybe_gc, call-on-entry
   debugging, and exit debugging/pop before calling funcall_general.
   Ffuncall provides exactly that complete boundary, so generated calls
   must go through it rather than calling funcall_general directly.  */
static Lisp_Object
zeln_funcall (ptrdiff_t nargs, Lisp_Object *args)
{
  return Ffuncall (nargs, args);
}

/* Hot-call shim for generated code.  The old JIT-to-JIT direct-entry
   optimization bypassed the interpreter's call boundary: it skipped
   quit checks, eval-depth accounting, backtrace frames, maybe_gc, and
   debugger entry/exit handling.  A recursive fixed-arity closure could
   therefore exhaust the C stack without ever raising
   `excessive-lisp-nesting'.

   Correctness comes first: route every generated call through
   Ffuncall.  The callee still reaches the same JIT entry through
   exec_byte_code once it is hot.  Reintroduce a direct fast path only
   by factoring a complete-call-boundary helper in eval.c, not by
   calling entry() from here.  */
static Lisp_Object
zeln_jit_call (ptrdiff_t nargs, Lisp_Object *args)
{
  return Ffuncall (nargs, args);
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

/* Bswitch jump resolution (bytecode.c:1743 CASE (Bswitch)): look KEY up
   in the defun's jump-table hash TABLE under the table's own test and
   return the target's ABSOLUTE bytecode offset, or -1 on a miss (the
   interpreter then falls through to the next opcode, which bytecomp
   always makes the `goto DEFAULT' after a byte-switch).  RAW return so
   the native side can dispatch on the offset with a plain i64 switch.
   hash_find covers every key type bytecomp puts in the table (fixnum,
   char, symbol, string) under eq/eql/equal -- exactly the
   interpreter's `else' branch; the count<=5 linear BASE_EQ path is a
   pure optimization with the same result.  */
static ptrdiff_t
zeln_switch_target (ptrdiff_t nargs, Lisp_Object *args)
{
  struct Lisp_Hash_Table *h = XHASH_TABLE (args[1]);
  ptrdiff_t i = hash_find (h, args[0]);
  if (i >= 0)
    return XFIXNUM (HASH_VALUE (h, i));
  return -1;
}

/* Per-opcode primitive shims.  Each wraps the C primitive the M1
   opcode maps to, behind the uniform MANY signature.  Calling the
   generic primitive directly (instead of the interpreter's fixnum
   inline fast path) is behaviorally identical: the fast path only
   short-circuits the common case and falls back to the SAME primitive
   on overflow / non-fixnum (bytecode.c:1331 Bplus, 1256 Beqlsign, ...).
   The differential test includes fixnum-overflow inputs to prove it.  */
static Lisp_Object zeln_times    (ptrdiff_t n, Lisp_Object *a) { return Ftimes    (n, a); }
static Lisp_Object zeln_sub1     (ptrdiff_t n, Lisp_Object *a) { return Fsub1     (a[0]); }
static Lisp_Object zeln_add1     (ptrdiff_t n, Lisp_Object *a) { return Fadd1     (a[0]); }
static Lisp_Object zeln_negate   (ptrdiff_t n, Lisp_Object *a) { return Fminus    (1, a); }
static Lisp_Object zeln_max      (ptrdiff_t n, Lisp_Object *a) { return Fmax      (n, a); }
static Lisp_Object zeln_min      (ptrdiff_t n, Lisp_Object *a) { return Fmin      (n, a); }
static Lisp_Object zeln_eqlsign  (ptrdiff_t n, Lisp_Object *a) { return Feqlsign  (n, a); }
static Lisp_Object zeln_gtr      (ptrdiff_t n, Lisp_Object *a) { return Fgtr      (n, a); }
static Lisp_Object zeln_lss      (ptrdiff_t n, Lisp_Object *a) { return Flss      (n, a); }
static Lisp_Object zeln_geq      (ptrdiff_t n, Lisp_Object *a) { return Fgeq      (n, a); }
static Lisp_Object zeln_leq      (ptrdiff_t n, Lisp_Object *a) { return Fleq      (n, a); }
static Lisp_Object zeln_plus     (ptrdiff_t n, Lisp_Object *a) { return Fplus     (n, a); }
static Lisp_Object zeln_minus    (ptrdiff_t n, Lisp_Object *a) { return Fminus    (n, a); }
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

/* bcall0 equivalent: bytecode.c:323 declares it `static`, so it is not
   visible here.  Replicate it — this is the EXACT unwind fn the
   interpreter passes to record_unwind_protect for a function-typed
   Bunwind_protect handler (bytecode.c:1017).  */
static void
zeln_bcall0 (Lisp_Object f)
{
  CALLN (Ffuncall, f);
}

/* ------------------------------------------------------------------ */
/* M2 per-opcode primitive shims.  Each wraps the SAME C primitive the
   interpreter's inline fast path falls back to (bytecode.c), behind the
   uniform MANY signature.  The fast path only short-circuits the common
   case and signals the SAME condition on failure, so calling the
   primitive directly is behaviorally identical (the differential gate
   proves it, including the error / throw inputs that cross a native
   frame).  */

/* Unary-on-TOP primitives (TOP = fn (a[0]); net stack effect 0).  */
static Lisp_Object zeln_symbol_value    (ptrdiff_t n, Lisp_Object *a) { return Fsymbol_value (a[0]); }
static Lisp_Object zeln_symbol_function (ptrdiff_t n, Lisp_Object *a) { return Fsymbol_function (a[0]); }
static Lisp_Object zeln_length          (ptrdiff_t n, Lisp_Object *a) { return Flength (a[0]); }
static Lisp_Object zeln_goto_char       (ptrdiff_t n, Lisp_Object *a) { return Fgoto_char (a[0]); }
static Lisp_Object zeln_char_after      (ptrdiff_t n, Lisp_Object *a) { return Fchar_after (a[0]); }
static Lisp_Object zeln_indent_to       (ptrdiff_t n, Lisp_Object *a) { return Findent_to (a[0], Qnil); }
static Lisp_Object zeln_forward_char    (ptrdiff_t n, Lisp_Object *a) { return Fforward_char (a[0]); }
static Lisp_Object zeln_forward_word    (ptrdiff_t n, Lisp_Object *a) { return Fforward_word (a[0]); }
static Lisp_Object zeln_forward_line    (ptrdiff_t n, Lisp_Object *a) { return Fforward_line (a[0]); }
static Lisp_Object zeln_char_syntax     (ptrdiff_t n, Lisp_Object *a) { return Fchar_syntax (a[0]); }
static Lisp_Object zeln_set_buffer      (ptrdiff_t n, Lisp_Object *a) { return Fset_buffer (a[0]); }
static Lisp_Object zeln_end_of_line     (ptrdiff_t n, Lisp_Object *a) { return Fend_of_line (a[0]); }
static Lisp_Object zeln_match_beginning (ptrdiff_t n, Lisp_Object *a) { return Fmatch_beginning (a[0]); }
static Lisp_Object zeln_match_end       (ptrdiff_t n, Lisp_Object *a) { return Fmatch_end (a[0]); }
static Lisp_Object zeln_upcase          (ptrdiff_t n, Lisp_Object *a) { return Fupcase (a[0]); }
static Lisp_Object zeln_downcase        (ptrdiff_t n, Lisp_Object *a) { return Fdowncase (a[0]); }
static Lisp_Object zeln_nreverse        (ptrdiff_t n, Lisp_Object *a) { return Fnreverse (a[0]); }
static Lisp_Object zeln_car_safe        (ptrdiff_t n, Lisp_Object *a) { return Fcar_safe (a[0]); }
static Lisp_Object zeln_cdr_safe        (ptrdiff_t n, Lisp_Object *a) { return Fcdr_safe (a[0]); }
/* Binsert (1-ary) and BinsertN (variadic) share this MANY shim.  */
static Lisp_Object zeln_insert          (ptrdiff_t n, Lisp_Object *a) { return Finsert (n, a); }

/* Binary primitives (POP v2; TOP = fn (a[0], a[1]); net stack effect -1).
   a[0] is the former TOS-1, a[1] the former TOS — the IR's emitBinary
   lays them out in that order so each shim's arg order matches the
   interpreter's `fn (TOP_after_pop, popped)`.  */
static Lisp_Object zeln_nth            (ptrdiff_t n, Lisp_Object *a) { return Fnth (a[0], a[1]); }
/* Belt: Felt (sequence, index) — arg order is the REVERSE of Fnth, so it
   needs its own shim even though both are binary.  */
static Lisp_Object zeln_elt            (ptrdiff_t n, Lisp_Object *a) { return Felt (a[0], a[1]); }
static Lisp_Object zeln_memq           (ptrdiff_t n, Lisp_Object *a) { return Fmemq (a[0], a[1]); }
static Lisp_Object zeln_string_equal   (ptrdiff_t n, Lisp_Object *a) { return Fstring_equal (a[0], a[1]); }
static Lisp_Object zeln_string_lessp   (ptrdiff_t n, Lisp_Object *a) { return Fstring_lessp (a[0], a[1]); }
static Lisp_Object zeln_nthcdr         (ptrdiff_t n, Lisp_Object *a) { return Fnthcdr (a[0], a[1]); }
static Lisp_Object zeln_member         (ptrdiff_t n, Lisp_Object *a) { return Fmember (a[0], a[1]); }
static Lisp_Object zeln_assq           (ptrdiff_t n, Lisp_Object *a) { return Fassq (a[0], a[1]); }
static Lisp_Object zeln_set            (ptrdiff_t n, Lisp_Object *a) { return Fset (a[0], a[1]); }
static Lisp_Object zeln_fset           (ptrdiff_t n, Lisp_Object *a) { return Ffset (a[0], a[1]); }
static Lisp_Object zeln_get            (ptrdiff_t n, Lisp_Object *a) { return Fget (a[0], a[1]); }
static Lisp_Object zeln_quo            (ptrdiff_t n, Lisp_Object *a) { return Fquo (n, a); }
static Lisp_Object zeln_rem            (ptrdiff_t n, Lisp_Object *a) { return Frem (a[0], a[1]); }
static Lisp_Object zeln_setcar         (ptrdiff_t n, Lisp_Object *a) { return Fsetcar (a[0], a[1]); }
static Lisp_Object zeln_setcdr         (ptrdiff_t n, Lisp_Object *a) { return Fsetcdr (a[0], a[1]); }
static Lisp_Object zeln_aref           (ptrdiff_t n, Lisp_Object *a) { return Faref (a[0], a[1]); }
static Lisp_Object zeln_skip_fwd      (ptrdiff_t n, Lisp_Object *a) { return Fskip_chars_forward (a[0], a[1]); }
static Lisp_Object zeln_skip_back     (ptrdiff_t n, Lisp_Object *a) { return Fskip_chars_backward (a[0], a[1]); }
static Lisp_Object zeln_buffer_substr (ptrdiff_t n, Lisp_Object *a) { return Fbuffer_substring (a[0], a[1]); }
static Lisp_Object zeln_delete_region (ptrdiff_t n, Lisp_Object *a) { return Fdelete_region (a[0], a[1]); }
static Lisp_Object zeln_narrow        (ptrdiff_t n, Lisp_Object *a) { return Fnarrow_to_region (a[0], a[1]); }

/* Variadic / ternary primitives (DISCARD n-1; fn called on &newtop).  */
static Lisp_Object zeln_concat        (ptrdiff_t n, Lisp_Object *a) { return Fconcat (n, a); }
static Lisp_Object zeln_nconc         (ptrdiff_t n, Lisp_Object *a) { return Fnconc (n, a); }
static Lisp_Object zeln_aset          (ptrdiff_t n, Lisp_Object *a) { return Faset (a[0], a[1], a[2]); }
static Lisp_Object zeln_substring     (ptrdiff_t n, Lisp_Object *a) { return Fsubstring (a[0], a[1], a[2]); }
static Lisp_Object zeln_set_marker    (ptrdiff_t n, Lisp_Object *a) { return Fset_marker (a[0], a[1], a[2]); }

/* 0-arg PUSH primitives (PUSH fn (); net stack effect +1).  The shim
   ignores its args; the IR passes nargs=0 and a dummy ptr.  Calling the
   F-primitive is result-identical to the interpreter's raw-macro form
   (e.g. Fpoint returns XSETFASTINT(PT) == make_fixed_natnum (PT)).  */
static Lisp_Object zeln_point           (ptrdiff_t n, Lisp_Object *a) { return Fpoint (); }
static Lisp_Object zeln_point_max       (ptrdiff_t n, Lisp_Object *a) { return Fpoint_max (); }
static Lisp_Object zeln_point_min       (ptrdiff_t n, Lisp_Object *a) { return Fpoint_min (); }
static Lisp_Object zeln_following_char  (ptrdiff_t n, Lisp_Object *a) { return Ffollowing_char (); }
static Lisp_Object zeln_preceding_char  (ptrdiff_t n, Lisp_Object *a) { return Fprevious_char (); }
static Lisp_Object zeln_current_column  (ptrdiff_t n, Lisp_Object *a) { return Fcurrent_column (); }
static Lisp_Object zeln_eolp            (ptrdiff_t n, Lisp_Object *a) { return Feolp (); }
static Lisp_Object zeln_eobp            (ptrdiff_t n, Lisp_Object *a) { return Feobp (); }
static Lisp_Object zeln_bolp            (ptrdiff_t n, Lisp_Object *a) { return Fbolp (); }
static Lisp_Object zeln_bobp            (ptrdiff_t n, Lisp_Object *a) { return Fbobp (); }
static Lisp_Object zeln_current_buffer  (ptrdiff_t n, Lisp_Object *a) { return Fcurrent_buffer (); }
static Lisp_Object zeln_widen           (ptrdiff_t n, Lisp_Object *a) { return Fwiden (); }

/* ------------------------------------------------------------------ */
/* specpdl-pure constructs (Tier 1 hard cases).  These do NOT transfer
   control; they only push/pop the global C specpdl, calling the SAME C
   helper the interpreter calls (set_internal / specbind / unbind_to /
   record_unwind_protect_excursion / record_unwind_current_buffer /
   save_restriction_save + record_unwind_protect / record_unwind_protect).
   Behavioral identity holds by construction.  Balance is guaranteed by
   bytecomp always emitting a matching Bunbind; Breturn does NOT touch
   specpdl, so the native Breturn just returns.  The native fn's alloca
   virtual stack means these helpers' effect is independent of where
   `top' lives.  */
static Lisp_Object zeln_varset  (ptrdiff_t n, Lisp_Object *a)
{ set_internal (a[0], a[1], Qnil, SET_INTERNAL_SET); return Qnil; }
static Lisp_Object zeln_varbind (ptrdiff_t n, Lisp_Object *a)
{ specbind (a[0], a[1]); return Qnil; }
/* Bunbind: the count comes in as `nargs' (the IR calls with nargs=arg).
   Mirror bytecode.c:851 unbind_to (specpdl_ref_add (SPECPDL_INDEX (),
   -arg), Qnil).  */
static Lisp_Object zeln_unbind  (ptrdiff_t n, Lisp_Object *a)
{ unbind_to (specpdl_ref_add (SPECPDL_INDEX (), -n), Qnil); return Qnil; }
static Lisp_Object zeln_save_excursion (ptrdiff_t n, Lisp_Object *a)
{ record_unwind_protect_excursion (); return Qnil; }
static Lisp_Object zeln_save_current_buffer (ptrdiff_t n, Lisp_Object *a)
{ record_unwind_current_buffer (); return Qnil; }
static Lisp_Object zeln_save_restriction (ptrdiff_t n, Lisp_Object *a)
{ record_unwind_protect (save_restriction_restore, save_restriction_save ()); return Qnil; }
/* Bunwind_protect: POP handler; record_unwind_protect (bcall0|prog_ignore,
   handler) — bytecode.c:1013-1019.  */
static Lisp_Object zeln_unwind_protect (ptrdiff_t n, Lisp_Object *a)
{ record_unwind_protect (FUNCTIONP (a[0]) ? zeln_bcall0 : prog_ignore, a[0]); return Qnil; }

/* ------------------------------------------------------------------ */
/* Tier 2 hard cases: catch / condition-case.  These resume via
   setjmp/longjmp.  The PROVEN-correct native translation is exactly
   what gccjit does (src/comp.c:2196 emit_limple_push_handler): the
   native fn calls push_handler, then sys_setjmp (&c->jmp) DIRECTLY IN
   THE NATIVE FN (not in this helper), and branches on the result.
   Because longjmp lands INSIDE the native fn's own setjmp call, the
   native stack frame and its alloca virtual stack survive (only C
   frames above are unwound) — this is why the virtual stack MUST be
   alloca'd in the native frame (M1 already does this), and why setjmp
   CANNOT live in this returning helper (its frame would be gone by the
   time a throw longjmps back).  unwind_to_catch (eval.c) has ALREADY
   restored the specpdl (unbind_to pdlcount) and the saved globals
   (lisp_eval_depth, ...) and set h->val BEFORE longjmp.

   zeln_pushhandler (the "setup" half):
     args[0] = tag       Lisp_Object: the catch tag / condition list
     args[1] = type      raw i64: 0 = CATCHER, 1 = CONDITION_CASE
     args[2] = top_slot  raw i64: &native fn's %top.slot alloca
   Returns the address of c->jmp (a sys_jmp_buf*) as a RAW i64 (XIL, so
   the bits pass straight through).  The native fn then calls _setjmp on
   it (sys_setjmp == _setjmp on this glibc target, HAVE__SETJMP first).

   zeln_resume (the "longjmp-caught" half, called by the native fn on the
   _setjmp-nonzero path): pops the handler, restores *top_slot to the
   pushtime top, and PUSHes the caught value — mirror bytecode.c:983-
   1003.  After it returns, the native fn's handler block runs with the
   caught value at TOS.  args[0] = top_slot (raw i64).  */
static Lisp_Object
zeln_pushhandler (ptrdiff_t nargs, Lisp_Object *args)
{
  Lisp_Object tag = args[0];
  enum handlertype type = (XLI (args[1]) != 0) ? CONDITION_CASE : CATCHER;
  Lisp_Object **top_slot = (Lisp_Object **) (intptr_t) XLI (args[2]);
  struct handler *c = push_handler (tag, type);
  c->bytecode_dest = 0;		/* sentinel: native resume, never the
				   interpreter's dest path.  */
  c->bytecode_top = *top_slot;	/* save current top VALUE */
  /* Hand the jmpbuf address back as a raw i64; the native fn calls
     _setjmp on it directly so longjmp lands in the native frame.  */
  return XIL ((EMACS_INT) (intptr_t) &c->jmp);
}

static Lisp_Object
zeln_resume (ptrdiff_t nargs, Lisp_Object *args)
{
  Lisp_Object **top_slot = (Lisp_Object **) (intptr_t) XLI (args[0]);
  struct handler *h = handlerlist;
  handlerlist = h->next;
  Lisp_Object caught = h->val;
  Lisp_Object *saved_top = h->bytecode_top;
  *top_slot = saved_top;	/* restore top to pushtime state */
  *++saved_top = caught;	/* PUSH caught value */
  *top_slot = saved_top;	/* top now points past the pushed value */
  return Qnil;
}

static Lisp_Object
zeln_pophandler (ptrdiff_t nargs, Lisp_Object *args)
{
  /* bytecode.c:1009-1011: normal-exit cleanup of the handler.  */
  handlerlist = handlerlist->next;
  return Qnil;
}

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
  /* ---- M2 surface (appended; order frozen — the hash fingerprints the
     ordered name list, so appending is safe but reordering is not). ---- */
  IDX_NTH,
  IDX_MEMQ,
  IDX_LENGTH,
  IDX_AREF,
  IDX_ASET,
  IDX_SYMBOL_VALUE,		/* Bvarref family AND Bsymbol_value */
  IDX_SYMBOL_FUNCTION,
  IDX_SET,
  IDX_FSET,
  IDX_GET,
  IDX_SUBSTRING,
  IDX_CONCAT,			/* Bconcat2/3/4/N */
  IDX_STRING_EQUAL,
  IDX_STRING_LESSP,
  IDX_NTHCDR,
  IDX_ELT,
  IDX_MEMBER,
  IDX_ASSQ,
  IDX_NREVERSE,
  IDX_SETCAR,
  IDX_SETCDR,
  IDX_CAR_SAFE,
  IDX_CDR_SAFE,
  IDX_NCONC,
  IDX_QUO,
  IDX_REM,
  IDX_GOTO_CHAR,
  IDX_INSERT,			/* Binsert (1-ary) AND BinsertN */
  IDX_CHAR_AFTER,
  IDX_INDENT_TO,
  IDX_FORWARD_CHAR,
  IDX_FORWARD_WORD,
  IDX_FORWARD_LINE,
  IDX_CHAR_SYNTAX,
  IDX_END_OF_LINE,
  IDX_MATCH_BEGINNING,
  IDX_MATCH_END,
  IDX_UPCASE,
  IDX_DOWNCASE,
  IDX_POINT,
  IDX_POINT_MAX,
  IDX_POINT_MIN,
  IDX_FOLLOWING_CHAR,
  IDX_PRECEDING_CHAR,
  IDX_CURRENT_COLUMN,
  IDX_EOLP,
  IDX_EOBP,
  IDX_BOLP,
  IDX_BOBP,
  IDX_CURRENT_BUFFER,
  IDX_SET_BUFFER,
  IDX_SKIP_CHARS_FORWARD,
  IDX_SKIP_CHARS_BACKWARD,
  IDX_BUFFER_SUBSTRING,
  IDX_DELETE_REGION,
  IDX_NARROW_TO_REGION,
  IDX_WIDEN,
  IDX_SET_MARKER,
  IDX_VARSET,			/* Bvarset family */
  IDX_VARBIND,			/* Bvarbind family */
  IDX_UNBIND,			/* Bunbind family (count in nargs) */
  IDX_SAVE_EXCURSION,
  IDX_SAVE_CURRENT_BUFFER,
  IDX_SAVE_RESTRICTION,
  IDX_UNWIND_PROTECT,
  IDX_PUSHHANDLER,		/* Bpushcatch + Bpushconditioncase (returns jmpbuf) */
  IDX_RESUME,			/* longjmp-caught path: restore top + push val */
  IDX_POPHANDLER,		/* Bpophandler */
  IDX_SWITCH_TARGET,		/* Bswitch: jump-table lookup -> raw offset/-1 */
  IDX_JIT_CALL,			/* validated JIT->JIT fixed-arity calls */
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
  /* ---- M2 surface (appended; arity is prin1-style like comp.c's
     comp--subr-signature, so the ABI hash is self-consistent). ---- */
  [IDX_NTH]              = { "nth",               "2",          (void *) &zeln_nth },
  [IDX_MEMQ]             = { "memq",              "2",          (void *) &zeln_memq },
  [IDX_LENGTH]           = { "length",            "1",          (void *) &zeln_length },
  [IDX_AREF]             = { "aref",              "2",          (void *) &zeln_aref },
  [IDX_ASET]             = { "aset",              "3",          (void *) &zeln_aset },
  [IDX_SYMBOL_VALUE]     = { "symbol-value",      "1",          (void *) &zeln_symbol_value },
  [IDX_SYMBOL_FUNCTION]  = { "symbol-function",   "1",          (void *) &zeln_symbol_function },
  [IDX_SET]              = { "set",               "2",          (void *) &zeln_set },
  [IDX_FSET]             = { "fset",              "2",          (void *) &zeln_fset },
  [IDX_GET]              = { "get",               "2",          (void *) &zeln_get },
  [IDX_SUBSTRING]        = { "substring",         "3",          (void *) &zeln_substring },
  [IDX_CONCAT]           = { "concat",            "(0 . many)", (void *) &zeln_concat },
  [IDX_STRING_EQUAL]     = { "string=",           "2",          (void *) &zeln_string_equal },
  [IDX_STRING_LESSP]     = { "string-lessp",      "2",          (void *) &zeln_string_lessp },
  [IDX_NTHCDR]           = { "nthcdr",            "2",          (void *) &zeln_nthcdr },
  [IDX_ELT]              = { "elt",               "2",          (void *) &zeln_elt },
  [IDX_MEMBER]           = { "member",            "2",          (void *) &zeln_member },
  [IDX_ASSQ]             = { "assq",              "2",          (void *) &zeln_assq },
  [IDX_NREVERSE]         = { "nreverse",          "1",          (void *) &zeln_nreverse },
  [IDX_SETCAR]           = { "setcar",            "2",          (void *) &zeln_setcar },
  [IDX_SETCDR]           = { "setcdr",            "2",          (void *) &zeln_setcdr },
  [IDX_CAR_SAFE]         = { "car-safe",          "1",          (void *) &zeln_car_safe },
  [IDX_CDR_SAFE]         = { "cdr-safe",          "1",          (void *) &zeln_cdr_safe },
  [IDX_NCONC]            = { "nconc",             "(0 . many)", (void *) &zeln_nconc },
  [IDX_QUO]              = { "/",                 "(0 . many)", (void *) &zeln_quo },
  [IDX_REM]              = { "%",                 "2",          (void *) &zeln_rem },
  [IDX_GOTO_CHAR]        = { "goto-char",         "1",          (void *) &zeln_goto_char },
  [IDX_INSERT]           = { "insert",            "(0 . many)", (void *) &zeln_insert },
  [IDX_CHAR_AFTER]       = { "char-after",        "1",          (void *) &zeln_char_after },
  [IDX_INDENT_TO]        = { "indent-to",         "1",          (void *) &zeln_indent_to },
  [IDX_FORWARD_CHAR]     = { "forward-char",      "1",          (void *) &zeln_forward_char },
  [IDX_FORWARD_WORD]     = { "forward-word",      "1",          (void *) &zeln_forward_word },
  [IDX_FORWARD_LINE]     = { "forward-line",      "1",          (void *) &zeln_forward_line },
  [IDX_CHAR_SYNTAX]      = { "char-syntax",       "1",          (void *) &zeln_char_syntax },
  [IDX_END_OF_LINE]      = { "end-of-line",       "1",          (void *) &zeln_end_of_line },
  [IDX_MATCH_BEGINNING]  = { "match-beginning",   "1",          (void *) &zeln_match_beginning },
  [IDX_MATCH_END]        = { "match-end",         "1",          (void *) &zeln_match_end },
  [IDX_UPCASE]           = { "upcase",            "1",          (void *) &zeln_upcase },
  [IDX_DOWNCASE]         = { "downcase",          "1",          (void *) &zeln_downcase },
  [IDX_POINT]            = { "point",             "0",          (void *) &zeln_point },
  [IDX_POINT_MAX]        = { "point-max",         "0",          (void *) &zeln_point_max },
  [IDX_POINT_MIN]        = { "point-min",         "0",          (void *) &zeln_point_min },
  [IDX_FOLLOWING_CHAR]   = { "following-char",    "0",          (void *) &zeln_following_char },
  [IDX_PRECEDING_CHAR]   = { "previous-char",     "0",          (void *) &zeln_preceding_char },
  [IDX_CURRENT_COLUMN]   = { "current-column",    "0",          (void *) &zeln_current_column },
  [IDX_EOLP]             = { "eolp",              "0",          (void *) &zeln_eolp },
  [IDX_EOBP]             = { "eobp",              "0",          (void *) &zeln_eobp },
  [IDX_BOLP]             = { "bolp",              "0",          (void *) &zeln_bolp },
  [IDX_BOBP]             = { "bobp",              "0",          (void *) &zeln_bobp },
  [IDX_CURRENT_BUFFER]   = { "current-buffer",    "0",          (void *) &zeln_current_buffer },
  [IDX_SET_BUFFER]       = { "set-buffer",        "1",          (void *) &zeln_set_buffer },
  [IDX_SKIP_CHARS_FORWARD]  = { "skip-chars-forward",  "2",     (void *) &zeln_skip_fwd },
  [IDX_SKIP_CHARS_BACKWARD] = { "skip-chars-backward", "2",     (void *) &zeln_skip_back },
  [IDX_BUFFER_SUBSTRING]    = { "buffer-substring",     "2",     (void *) &zeln_buffer_substr },
  [IDX_DELETE_REGION]       = { "delete-region",        "2",     (void *) &zeln_delete_region },
  [IDX_NARROW_TO_REGION]    = { "narrow-to-region",     "2",     (void *) &zeln_narrow },
  [IDX_WIDEN]               = { "widen",                "0",     (void *) &zeln_widen },
  [IDX_SET_MARKER]          = { "set-marker",           "3",     (void *) &zeln_set_marker },
  [IDX_VARSET]              = { "zeln-varset",          "(2 . many)", (void *) &zeln_varset },
  [IDX_VARBIND]             = { "zeln-varbind",         "(2 . many)", (void *) &zeln_varbind },
  [IDX_UNBIND]              = { "zeln-unbind",          "(1 . many)", (void *) &zeln_unbind },
  [IDX_SAVE_EXCURSION]      = { "zeln-save-excursion",  "(0 . many)", (void *) &zeln_save_excursion },
  [IDX_SAVE_CURRENT_BUFFER] = { "zeln-save-current-buffer", "(0 . many)", (void *) &zeln_save_current_buffer },
  [IDX_SAVE_RESTRICTION]    = { "zeln-save-restriction",   "(0 . many)", (void *) &zeln_save_restriction },
  [IDX_UNWIND_PROTECT]      = { "zeln-unwind-protect",     "(1 . many)", (void *) &zeln_unwind_protect },
  [IDX_PUSHHANDLER]         = { "zeln-pushhandler",        "(3 . many)", (void *) &zeln_pushhandler },
  [IDX_RESUME]              = { "zeln-resume",             "(1 . many)", (void *) &zeln_resume },
  [IDX_POPHANDLER]          = { "zeln-pophandler",         "(0 . many)", (void *) &zeln_pophandler },
  [IDX_SWITCH_TARGET]       = { "zeln-switch-target",      "2",          (void *) &zeln_switch_target },
  [IDX_JIT_CALL]            = { "zeln-jit-call",           "(0 . many)", (void *) &zeln_jit_call },
};

static void
zeln_freloc_check_fill (void)
{
  if (zeln_freloc.size)
    return;
  /* The Tier-1 .zeln inline fast paths (emitBinaryArith / emitUnaryArith
     for fixnum-arith, emitConsSlot for Bcar/Bcdr in
     tools/zeln-compile/src/main.zig) bake the USE_LSB_TAG representation
     directly into the emitted .ll: Lisp_Int0 low-2-bits tagging + XFIXNUM
     ashift (fixnum-arith), and CONSP = (x & 7) == 3 + XCONS = x & -8 +
     car@0/cdr@8 slot reads (cons-slot).  A non-LSB build would miscompute
     those tags, so fail loud at the first .zeln load rather than misbehave.
     Assert-only (no-op in a non-ENABLE_CHECKING build); no ABI impact, no
     freloc-surface change.  */
  eassert (USE_LSB_TAG);
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
     mirroring comp.c:787-793.  ZELN_ABI_VERSION ("Z8" current; "Z7"
     added Bswitch, "Z4" covered M2b, "Z3" covered M2, "Z2" M1,
     "Z1" M0) is the
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

/* Fread ONE fn's const blob (a vector in read-syntax) and scatter it
   into fe->d_reloc[0..n_d_reloc).  Mirrors comp.c:5318+5322
   (comp_u->data_vec = load_static_obj (...); data_relocs[i] = AREF).  */

/* GC root: every constant vector reconstructed by zeln_fill_d_reloc_fn is
   consed onto this list so the constants stay reachable.  Each native fn
   reads its constants from its .zeln's `d_reloc' array, which lives in the
   shared object's static (GC-invisible) memory and holds the SAME
   Lisp_Objects as the vector produced by Fread.  Without this root, a GC
   after load sweeps any freshly-Fread heap object (cons cells, strings,
   records) that is referenced ONLY from `d_reloc', leaving the static array
   pointing at freed memory -> corrupt Lisp_Objects (the M2b gate #2
   cl-remove->cl-delete SIGABRT).  Emacs GC is non-moving, so the addresses
   baked into `d_reloc' stay valid as long as the objects are alive -- which
   rooting the vectors guarantees.  This mirrors how gccjit comp.c GC-traces
   each native fn's data relocs through its compiled-function vector.
   staticpro'd in syms_of_compz.  */
static Lisp_Object zeln_loaded_const_vectors;

/* M2b.5 gate-#2 instrumentation: how many .zeln units were genuinely
   loaded (Fcomp_z_load_zeln ran to completion, i.e. at least one native
   fn was Ffset).  check-zeln (run-check.zig with ZELN_LOAD_PATH set)
   fails the run when this stays 0, so a silent interpreter fallback
   (e.g. a cache populated with zero .zeln because every link failed)
   can no longer pass the 582-via-.zeln gate trivially.  Declared by
   globals.h from the DEFVAR_INT below (make-docfile), like
   native_comp_z_prefer; no manual declaration here.  */

static void
zeln_fill_d_reloc_fn (zeln_fn_entry_t *fe)
{
  zeln_static_obj_t *blob = fe->d_reloc_blob;
  if (!blob || blob->len == 0)
    return;
  Lisp_Object vec = Fread (make_string (blob->data, blob->len));
  if (NILP (vec) || NILP (Fvectorp (vec)))
    xsignal1 (Qnative_lisp_file_inconsistent,
	      build_string ("zeln: malformed d_reloc blob"));
  ptrdiff_t n = XFIXNUM (Flength (vec));
  if (n != fe->n_d_reloc)
    xsignal1 (Qnative_lisp_file_inconsistent,
	      build_string ("zeln: d_reloc count mismatch"));
  for (ptrdiff_t i = 0; i < n; i++)
    fe->d_reloc[i] = AREF (vec, i);
  /* Root the vector so GC cannot collect the heap objects `d_reloc' now
     aliases (see zeln_loaded_const_vectors).  `vec' is on the C stack, so
     it is protected across the Fcons allocation; the returned cons (car =
     vec) is then held by the static root.  */
  zeln_loaded_const_vectors = Fcons (vec, zeln_loaded_const_vectors);
}

/* Verify the .zeln's baked ABI hash matches the running emacs's
   Vzeln_abi_hash.  Mirror comp.c:5303-5305 (LINK_TABLE_HASH_SYM gate).  */
static void
zeln_verify_hash (zeln_entry_t *e)
{
  Lisp_Object file_hash = make_string (e->freloc_hash_z, 8);
  if (NILP (Fstring_equal (file_hash, Vzeln_abi_hash)))
    xsignal1 (Qnative_lisp_file_inconsistent,
	      concat3 (make_string (e->freloc_hash_z, 8),
		       build_string (" runtime="), Vzeln_abi_hash));
}

/* Forward decls: Fcomp_z_load_zeln registers a unit for FDO watching
   (defined below, after the loader).  */
static bool zeln_fdo_enabled (void);
static void zeln_fdo_register (zeln_entry_t *, dynlib_handle_ptr,
			       Lisp_Object, Lisp_Object);

/* Close a .zeln only while it is still safe to do so.  Once any native
   function from the unit has been installed in a symbol function cell,
   ownership transfers to the session: a signal during the rest of load
   must not unmap code that Lisp can still call.  */
struct zeln_load_handle_state
{
  dynlib_handle_ptr handle;
  bool installed;
};

static void
zeln_unwind_load_handle (void *arg)
{
  struct zeln_load_handle_state *state = arg;
  if (!state->installed && state->handle)
    {
      dynlib_close (state->handle);
      state->handle = NULL;
    }
}

/* Legitimate Lisp files can defalias the same name more than once; the
   loader installs entries in source order so the final definition wins.
   Such names are safe for normal loads but ambiguous for FDO's name-based
   pairing after a PGO hot-first reorder, so those units are not watched.  */
static bool
zeln_entry_has_duplicate_fn_names (const zeln_entry_t *e)
{
  for (ptrdiff_t i = 0; i < e->n_fns; i++)
    for (ptrdiff_t j = 0; j < i; j++)
      if (e->fns[i].symbol_name && e->fns[j].symbol_name
	  && strcmp (e->fns[i].symbol_name,
		     e->fns[j].symbol_name) == 0)
	return true;
  return false;
}

DEFUN ("comp-z-load-zeln", Fcomp_z_load_zeln, Scomp_z_load_zeln, 1, 1, 0,
       doc: /* Load a .zeln native-comp unit (Zig path).
FILE is the .zeln path.  The unit holds N native functions (one per
defun in the source .elc) plus the .elc's non-defun top-level forms as a
read-syntax blob.  This loader dlopens the .zeln, verifies the ABI hash,
patches the freloc table, reconstructs each fn's constants, Ffsets each
native fn under its baked defun symbol, and Fread+Feval the top-level
blob under the load-file-name / load-history Fload already bound.  The
returned value is the LAST fset subr (the zeln-diff harness funcalls it
for its single-fn .zeln; the transparent Fload path ignores the return).
For internal use.  */)
  (Lisp_Object file)
{
  CHECK_STRING (file);
  /* ASCII paths need no file-name encoding, so dynlib_open_for_eln gets
     the raw SSDATA bytes.  dynlib_open_for_eln (RTLD_LAZY, no RTLD_GLOBAL)
     is the .eln/.zeln loader contract (tools/emacs-dynlib doc): the .zeln
     must not leak its internal symbols into the global namespace.  */
  dynlib_handle_ptr handle = dynlib_open_for_eln (SSDATA (file));
  if (!handle)
    xsignal1 (Qnative_lisp_file_inconsistent,
	      build_string (dynlib_error () ? dynlib_error ()
					    : "dynlib_open failed"));
  struct zeln_load_handle_state handle_state = { handle, false };
  specpdl_ref load_count = SPECPDL_INDEX ();
  record_unwind_protect_ptr (zeln_unwind_load_handle, &handle_state);

  zeln_entry_t *(*entry_sym) (void) =
    (zeln_entry_t * (*) (void)) dynlib_sym (handle, "zeln_entry");
  if (!entry_sym)
    xsignal1 (Qnative_lisp_file_inconsistent,
	      build_string ("no zeln_entry symbol"));

  zeln_entry_t *e = entry_sym ();
  if (!e)
    xsignal1 (Qnative_lisp_file_inconsistent,
	      build_string ("zeln_entry returned NULL"));

  /* Order mirrors comp.c load_comp_unit: hash gate, then patch relocs,
     then reconstruct data.  The hash gate fires first so a stale-ABI
     .zeln is rejected before any native code can run.  */
  hash_zeln_abi ();
  zeln_verify_hash (e);
  zeln_patch_freloc (e);

  /* When both native backends are compiled in, expose a .zeln through the
     same Lisp-visible native-comp-unit metadata as a .eln.  This lets
     help/introspection (native-comp-function-p, subr-native-comp-unit,
     native-comp-unit-file) treat a .zeln like its .eln counterpart.  The
     unit is retained by its subrs; initialize the GC-traced slots used by
     eln code paths to benign values and record the actual .zeln file.  */
#ifdef HAVE_NATIVE_COMP
  struct Lisp_Native_Comp_Unit *cu = allocate_native_comp_unit ();
  Lisp_Object comp_unit;
  XSETNATIVE_COMP_UNIT (comp_unit, cu);
  {
    cu->file = file;
    cu->optimize_qualities = Qnil;
    cu->lambda_gc_guard_h = CALLN (Fmake_hash_table, QCtest, Qeq);
    cu->lambda_c_name_idx_h = CALLN (Fmake_hash_table, QCtest, Qequal);
    cu->data_vec = Qnil;
    /* Leave handle NULL: zeln owns dlopen/dlclose lifetime (including FDO
       hot swaps).  This metadata unit is for Lisp introspection only.  */
    cu->handle = NULL;
  }
#endif

  /* Wrap each native fn into a freshly-allocated subr and Ffset it
     under its baked defun symbol.  The fn's REAL arity (decoded from
     args_template) is installed into min_args/max_args — mirroring
     gccjit's comp.c make_subr — so `func-arity' reports the truth; the
     function slot carries the .zeln's arity-honest native_entry (an
     exact-arity trampoline for no-&rest arities with max <= 8, the
     MANY body itself otherwise), so funcall's dispatch-by-max_args
     reaches a matching signature.  The native fn's prologue
     (zeln_setup_args) remains the enforcer — identical arity errors.
     ALLOCATE_PLAIN_PSEUDOVECTOR sets lisplen=0, so GC traces none of the
     subr's Lisp_Object slots; memclear zeroes the non-header fields
     defensively (backtrace / doc lookup may read symbol_name / doc).  */
  Lisp_Object last_subr = Qnil;
  Lisp_Object subr_list = Qnil;	/* FDO: subrs in fn-table order */
  for (ptrdiff_t i = 0; i < e->n_fns; i++)
    {
      zeln_fn_entry_t *fe = &e->fns[i];
      zeln_fill_d_reloc_fn (fe);
      struct Lisp_Subr *subr =
	ALLOCATE_PLAIN_PSEUDOVECTOR (struct Lisp_Subr, PVEC_SUBR);
      memclear (&subr->function,
		sizeof (*subr) - offsetof (struct Lisp_Subr, function));
      bool rest = (fe->args_template & 128) != 0;
      int mandatory = fe->args_template & 127;
      ptrdiff_t nonrest = fe->args_template >> 8;
      subr->function.aMANY = fe->native_entry;
      subr->min_args = mandatory;
      subr->max_args = (rest || nonrest > 8) ? MANY : nonrest;
#ifdef HAVE_NATIVE_COMP
      subr->native_comp_u = comp_unit;
      subr->native_c_name = xstrdup (fe->symbol_name);
      subr->type = Qfunction;
#endif
      /* Ffset the native fn under its baked defun symbol so loading the
	 .zeln leaves every defun natively callable, mirroring how loading
	 the .elc would fset each via its top-level `defalias'.  */
      Lisp_Object sym = Fintern (build_string (fe->symbol_name), Qnil);
      /* subr->symbol_name is a plain C char*: the interned symbol's
	 name Lisp_Object stays stable, but the .zeln's baked
	 fe->symbol_name points into the .zeln's static memory, which the
	 FDO hot-swap dlcloses — leaving the subr's name dangling when
	 the next swap must match it.  Copy into malloc'd memory that
	 outlives the .zeln (bounded by ZELN_FDO_MAX_UNITS units).  */
      subr->symbol_name = xstrdup (fe->symbol_name);
      Lisp_Object subr_obj;
      XSETSUBR (subr_obj, subr);
      handle_state.installed = true;
      Ffset (sym, subr_obj);
      last_subr = subr_obj;
      subr_list = Fcons (subr_obj, subr_list);
    }
  subr_list = Fnreverse (subr_list);

  /* Replay the .elc's non-defun top-level forms (provide / defvar /
     require / autoload / defcustom / ...).  Vload_file_name and
     Vcurrent_load_list are already bound by Fload (specbind at
     lread.c:1544/1057) to the reconstructed .elc, so load-file-name /
     load-history report the .elc, not the .zeln.  The blob is a single
     (progn ...) form (empty/zero-len for the M0/M1 single-fn .zeln).  */
  zeln_static_obj_t *tb = e->top_level_blob;
  if (tb && tb->len > 0)
    {
      Lisp_Object form = Fread (make_string (tb->data, tb->len));
      if (!NILP (form))
	Feval (form, Qnil);
    }

  zeln_load_count++;

  /* FDO: if auto-optimization is configured, watch this unit (flips
     its fdo_active flag; native fns start counting calls).  The
     rel-name (basename of the .zeln) names the profile + recompiled
     artifact under zeln_auto_fdo_path.  A raw basename scan instead of
     Ffile_name_nondirectory: this runs during Fload with no usable
     current-buffer context, and the file arg is an absolute ASCII path
     on every loader call site (the swap path, the transparent Fload
     path, and the FDO recompile spawn all pass absolute paths).  */
  if (zeln_fdo_enabled () && ! zeln_entry_has_duplicate_fn_names (e))
    {
      const char *s = SSDATA (file);
      const char *slash = strrchr (s, '/');
      Lisp_Object rel = build_string (slash ? slash + 1 : s);
      zeln_fdo_register (e, handle, subr_list, rel);
    }

  unbind_to (load_count, Qnil);

  return last_subr;
}

/* ------------------------------------------------------------------ */
/* FDO — auto profile-guided recompilation (Z5).  The loader watches
   every loaded .zeln: when zeln_auto_fdo_path is set AND
   zeln_auto_fdo_profile is non-nil, it flips the unit's fdo_active
   flag (the .zeln's native fns then increment their per-fn counters,
   ~2 cycles/call) and, at post-GC intervals (zeln_auto_fdo_interval),
   flushes the counters to a profile file, recompiles the unit with
   zeln-compile --profile (hot-first layout + !prof weights), and
   hot-swaps the subr function pointers to the tuned .zeln.  The last
   round passes --final (counters dropped).  Strategy/stop: a unit is
   recompiled at most ZELN_FDO_MAX_ROUNDS times; when the profile shows
   no fn above the zeln_auto_fdo_profile threshold (or max rounds is
   reached) auto-optimization for that unit stops.  All of this is
   OFF by default (path nil => the flags stay 0 and the counters'
   load+icmp+branch falls through).  */

#define ZELN_FDO_MAX_ROUNDS 2

/* One loaded unit being auto-optimized.  Retired handles are never
   dlclosed: a helper called by old generated code can allocate, enter
   GC, and return through that code after the post-GC swap has finished.
   At that point the old frame is still live even though every symbol
   now points to the new unit.  The bounded number of FDO rounds makes
   keeping the old mappings a small, deterministic cost.  */
typedef struct
{
  dynlib_handle_ptr handle;	/* current .zeln handle */
  zeln_entry_t *entry;		/* current entry (fn table + fdo fields) */
  Lisp_Object subrs;		/* list of subr objects, in fn-table order */
  Lisp_Object rel_name;		/* .zeln rel-filename (profile naming) */
  double last_check;		/* wall-clock of last flush/recompile */
  int rounds;			/* recompiles performed */
  bool active;			/* fdo_active was flipped for this unit */
} zeln_fdo_unit_t;

#define ZELN_FDO_MAX_UNITS 64
/* Each unit can retire at most ZELN_FDO_MAX_ROUNDS handles; the +1 is
   defensive and keeps the bound obvious without a dynamic allocator. */
#define ZELN_FDO_MAX_RETIRED_HANDLES \
  (ZELN_FDO_MAX_UNITS * (ZELN_FDO_MAX_ROUNDS + 1))
static zeln_fdo_unit_t zeln_fdo_units[ZELN_FDO_MAX_UNITS];
static ptrdiff_t zeln_fdo_nunits;
static dynlib_handle_ptr zeln_fdo_retired_handles[ZELN_FDO_MAX_RETIRED_HANDLES];
static ptrdiff_t zeln_fdo_nretired;

/* GC root for the FDO units' subr lists + rel-names.  Each unit's
   `subrs' / `rel_name' fields are Lisp objects living only in C struct
   fields — invisible to GC — so without this root the cons cells (and
   the rel-name string, which is referenced ONLY here) would be swept
   between load and the hot-swap (the recompile spawn + intervening GCs
   destroy them; the subr OBJECTS themselves stay alive via the symbols
   they're Ffset to, but the list scaffolding and rel-name do not).
   staticpro'd in syms_of_compz; a single list holding every unit's
   subr list, with the rel-names in a parallel root.  */
static Lisp_Object zeln_fdo_subrs_root;
static Lisp_Object zeln_fdo_names_root;

/* Config (DEFVAR'd in syms_of_compz): zeln_auto_fdo_path (dir for
   profiles + recompiled .zeln; nil = off), zeln_auto_fdo_interval
   (min seconds between post-GC checks; default 60),
   zeln_auto_fdo_profile (nil = no collection; t = collect with the
   default hot threshold 1000; number N = hot threshold N).  The
   DEFVAR_* declarations below make make-docfile emit `#define
   Vzeln_auto_fdo_path globals.f_...' into globals.h (like
   Vzeln_abi_hash / zeln_load_count), so there is NO manual
   declaration here.  */

/* True when the FDO machinery should be active at all.  */
static bool
zeln_fdo_enabled (void)
{
  return (STRINGP (Vzeln_auto_fdo_path) && !NILP (Vzeln_auto_fdo_profile));
}

/* The hot threshold: N from zeln_auto_fdo_profile, or the default.  */
static uint64_t
zeln_fdo_threshold (void)
{
  if (FIXNUMP (Vzeln_auto_fdo_profile))
    return XFIXNUM (Vzeln_auto_fdo_profile) > 0 ? XFIXNUM (Vzeln_auto_fdo_profile) : 1;
  return 1000;
}

/* Register a freshly-loaded unit for FDO watching.  Called by
   Fcomp_z_load_zeln when zeln_fdo_enabled; flips the unit's active
   flag so its native fns start counting calls.  */
static void
zeln_fdo_register (zeln_entry_t *e, dynlib_handle_ptr handle,
		   Lisp_Object subr_list, Lisp_Object rel_name)
{
  if (zeln_fdo_nunits >= ZELN_FDO_MAX_UNITS)
    return;
  zeln_fdo_unit_t *u = &zeln_fdo_units[zeln_fdo_nunits++];
  u->handle = handle;
  u->entry = e;
  u->subrs = subr_list;
  /* Root the list: cons cells referenced only from the C struct field
     would be swept by the next GC (the subr OBJECTS survive via their
     symbols, the list scaffolding does not).  */
  zeln_fdo_subrs_root = Fcons (subr_list, zeln_fdo_subrs_root);
  zeln_fdo_names_root = Fcons (rel_name, zeln_fdo_names_root);
  u->rel_name = rel_name;
  u->last_check = 0.0;
  u->rounds = 0;
  u->active = false;
  if (e->fdo_active)
    {
      *e->fdo_active = 1;
      u->active = true;
    }
}

/* Write the profile file `<path>/<rel>.zprofile': one `fnname<TAB>count'
   line per fn (read by zeln-compile --profile).  Returns the highest
   count seen.  */
static uint64_t
zeln_fdo_write_profile (const char *path, zeln_entry_t *e)
{
  FILE *f = emacs_fopen (path, "w");
  if (!f)
    return 0;
  uint64_t maxc = 0;
  for (ptrdiff_t i = 0; i < e->n_fns; i++)
    {
      uint64_t c = e->fdo_counters ? e->fdo_counters[i] : 0;
      uint64_t fb = e->fdo_fallbacks ? e->fdo_fallbacks[i] : 0;
      if (c > maxc)
	maxc = c;
      fprintf (f, "%s\t%" PRIu64 "\t%" PRIu64 "\n",
	       e->fns[i].symbol_name, c, fb);
    }
  emacs_fclose (f);
  return maxc;
}

/* Reset all counters of a unit (called after a flush / after a swap
   so the next interval measures fresh).  */
static void
zeln_fdo_reset_counters (zeln_entry_t *e)
{
  if (!e->fdo_counters)
    return;
  for (ptrdiff_t i = 0; i < e->n_fns; i++)
    e->fdo_counters[i] = 0;
  if (e->fdo_fallbacks)
    for (ptrdiff_t i = 0; i < e->n_fns; i++)
      e->fdo_fallbacks[i] = 0;
}

/* Spawn zeln-compile over the unit's embedded zunit + manifest, with
   --profile (or --final on the last round), producing OUT.  The
   zeln-compile exe comes from the ZELN_COMPILE env var (absolute
   path, like zeln-bench) with a PATH fallback.  Returns true on
   success.  Runs at post-GC (no Lisp in flight); Fcall_process is
   safe there (inhibit_garbage_collection is in effect).  */
static bool
zeln_fdo_recompile (zeln_fdo_unit_t *u, const char *out, bool final)
{
  zeln_entry_t *e = u->entry;
  if (!e->zunit_blob || e->zunit_blob->len == 0)
    return false;

  /* The recompile inputs land next to the output: <out>.zunit,
     <out>.manifest, <out>.zprofile.  Sizes are exact (len + suffix +
     NUL), not magic +8/+12, so a suffix change cannot overflow.  */
  const char *zu_suf = ".zunit", *mf_suf = ".manifest", *pf_suf = ".zprofile";
  char *zu = xmalloc (strlen (out) + strlen (zu_suf) + 1);
  char *mf = xmalloc (strlen (out) + strlen (mf_suf) + 1);
  char *pf = xmalloc (strlen (out) + strlen (pf_suf) + 1);
  sprintf (zu, "%s%s", out, zu_suf);
  sprintf (mf, "%s%s", out, mf_suf);
  sprintf (pf, "%s%s", out, pf_suf);

  FILE *f = emacs_fopen (zu, "wb");
  if (f)
    {
      fwrite (e->zunit_blob->data, 1, e->zunit_blob->len, f);
      emacs_fclose (f);
    }
  f = emacs_fopen (mf, "w");
  if (f)
    {
      hash_zeln_abi ();
      fprintf (f, "%s\n%s\n%s\n", ZELN_ABI_VERSION,
	       SSDATA (zeln_signature_string ()), SSDATA (Vzeln_abi_hash));
      emacs_fclose (f);
    }
  zeln_fdo_write_profile (pf, e);

  /* Build the argv: zeln-compile <zunit> <manifest> <out> [--profile
     <pf> | --final].  Spawn via Fcall_process with the standard
     layout (PROGRAM INFILE DESTINATION DISPLAY ARGS...): indices 1-3
     are the redirection slots (Qnil = null-device in / discard out),
     index 4+ are the program's ARGS.  Safe at post-GC
     (inhibit_garbage_collection is in effect).  Fcall_process resolves
     the PROGRAM via exec-path, NOT the cwd, so a relative ZELN_COMPILE
     (e.g. "zig-out/bin/zeln-compile" from the build step) must be
     expanded to an absolute path first -- the same reason the harness
     (build-aux/zeln-fdo.el) expands it.  */
  const char *zraw = getenv ("ZELN_COMPILE");
  Lisp_Object zc = zraw ? build_string (zraw) : build_string ("zeln-compile");
  zc = Fexpand_file_name (zc, Qnil);
  Lisp_Object argv[10];
  int nargs = 8;
  argv[0] = zc;
  argv[1] = Qnil;		/* INFILE */
  argv[2] = Qnil;		/* DESTINATION */
  argv[3] = Qnil;		/* DISPLAY */
  argv[4] = build_string (zu);
  argv[5] = build_string (mf);
  argv[6] = build_string (out);
  if (final)
    {
      /* The final round keeps the profile-guided layout (hot-first +
	 branch weights) but drops the counters: both flags.  */
      argv[7] = build_string ("--profile");
      argv[8] = build_string (pf);
      argv[9] = build_string ("--final");
      nargs = 10;
    }
  else
    {
      argv[7] = build_string ("--profile");
      argv[8] = build_string (pf);
      nargs = 9;
    }

  xfree (zu); xfree (mf); xfree (pf);

  Lisp_Object rc = Fcall_process (nargs, argv);
  return EQ (rc, make_fixnum (0));
}

/* Hot-swap a unit to a freshly recompiled .zeln: dlopen OUT, verify
   the hash, patch freloc, and repoint every existing subr's function
   pointer to the new native code.  Constant identity is preserved:
   the NEW fn's d_reloc arrays are filled with the OLD Lisp_Object
   values (the loader does not Fread the new blob — it copies the old
   values, which are identical objects).  Returns true on success.  */
static bool
zeln_fdo_swap (zeln_fdo_unit_t *u, const char *out)
{
  ptrdiff_t nold = u->entry->n_fns;
  ptrdiff_t nnew;
  dynlib_handle_ptr nh = dynlib_open_for_eln (out);
  if (!nh)
    return false;
  hash_zeln_abi ();
  zeln_entry_t *(*entry_sym) (void) =
    (zeln_entry_t * (*) (void)) dynlib_sym (nh, "zeln_entry");
  if (!entry_sym)
    {
	  dynlib_close (nh);
	  return false;
	}
  zeln_entry_t *ne = entry_sym ();
  nnew = ne ? ne->n_fns : 0;
  if (!ne || !ne->fdo_counters || !ne->fdo_fallbacks || nnew != nold)
    {
      dynlib_close (nh);
      return false;
    }
  if (SBYTES (Vzeln_abi_hash) != 8
      || memcmp (ne->freloc_hash_z, SSDATA (Vzeln_abi_hash), 8) != 0)
    {
      dynlib_close (nh);
      return false;
    }
  /* Validate before changing either library's mutable state.  In
     particular, do not patch/repoint until every old function has a
     unique counterpart with the same arity and constant count.  A
     duplicate serializer name would make name-based pairing ambiguous,
     so refuse to optimize that unit rather than guessing.  */
  for (ptrdiff_t i = 0; i < nold; i++)
    {
      zeln_fn_entry_t *ofe = &u->entry->fns[i];
      ptrdiff_t old_matches = 0, new_matches = 0;
      zeln_fn_entry_t *nfe = NULL;
      if (!ofe->symbol_name || ofe->n_d_reloc < 0)
	goto fail;
      for (ptrdiff_t j = 0; j < nold; j++)
	if (u->entry->fns[j].symbol_name
	    && strcmp (ofe->symbol_name, u->entry->fns[j].symbol_name) == 0)
	  old_matches++;
      for (ptrdiff_t j = 0; j < nnew; j++)
	{
	  zeln_fn_entry_t *cand = &ne->fns[j];
	  if (!cand->symbol_name || !cand->native_entry
	      || !cand->d_reloc || cand->n_d_reloc < 0)
	    goto fail;
	  if (strcmp (ofe->symbol_name, cand->symbol_name) == 0)
	    {
	      new_matches++;
	      nfe = cand;
	    }
	}
      if (old_matches != 1 || new_matches != 1 || !nfe
	  || nfe->n_d_reloc != ofe->n_d_reloc
	  || nfe->args_template != ofe->args_template)
	goto fail;
    }

  zeln_patch_freloc (ne);

  /* Repoint every subr; copy the old d_reloc values into the new
     arrays (identity: same Lisp_Objects, no fresh Fread).  Match by
     SYMBOL NAME, never by table index: the PGO recompile emits the fn
     table HOT-FIRST (main.zig `order`), so new slot i is generally NOT
     the same fn as old slot i.  Index pairing would hand each symbol
     the wrong native code + a crossed d_reloc constant vector.  The
     validation pass has already proved names are unique and every
     field is compatible.  */
  Lisp_Object tail = u->subrs;
  for (; !NILP (tail); tail = XCDR (tail))
    {
      struct Lisp_Subr *subr = XSUBR (XCAR (tail));
      const char *sym = subr->symbol_name;
      for (ptrdiff_t j = 0; j < ne->n_fns; j++)
	{
	  zeln_fn_entry_t *nfe = &ne->fns[j];
	  if (strcmp (sym, nfe->symbol_name) != 0)
	    continue;
	  /* The arity never changes across swaps (same fn), so min/max stay;
	     repoint the function slot at the new unit's arity-honest entry.  */
	  subr->function.aMANY = nfe->native_entry;
	  /* Copy the old d_reloc values into this new entry's array:
	     identity preserved (same Lisp_Objects, only the table order
	     changed).  The old entry lives in u->entry->fns.  */
	  for (ptrdiff_t k = 0; k < u->entry->n_fns; k++)
	    if (strcmp (sym, u->entry->fns[k].symbol_name) == 0)
	      {
		zeln_fn_entry_t *ofe = &u->entry->fns[k];
		if (ofe->n_d_reloc == nfe->n_d_reloc)
		  memcpy (nfe->d_reloc, ofe->d_reloc,
			  ofe->n_d_reloc * sizeof (Lisp_Object));
		break;
	      }
	  break;
	}
    }

  /* Retire, never close: symbol dispatch now points at the new unit,
     but an old generated frame reached through a helper/GC can still be
     on the C stack and may execute after this function returns.  */
  if (zeln_fdo_nretired < ZELN_FDO_MAX_RETIRED_HANDLES)
    zeln_fdo_retired_handles[zeln_fdo_nretired++] = u->handle;
  u->handle = nh;
  u->entry = ne;
  u->rounds++;
  u->last_check = 0.0;
  /* The new .zeln's counters are gated by ITS fdo_active flag, which
     starts 0 (fresh artifact): re-flip it so collection continues for
     the next round (the final round's --final drops the counters, so
     this is a no-op there — no branch exists to gate).  */
  if (u->active && ne->fdo_active)
    *ne->fdo_active = 1;
  zeln_fdo_reset_counters (ne);
  return true;

 fail:
  dynlib_close (nh);
  return false;
}

/* The post-GC FDO check: interval-gated flush + threshold recompile +
   hot-swap.  Called from garbage_collect (alloc.c) after the sweep,
   under HAVE_NATIVE_COMP_ZIG.  Cheap when disabled: one stringp check
   when path/profile are nil.  */
void
zeln_fdo_gc_check (void)
{
  if (!zeln_fdo_enabled () || zeln_fdo_nunits == 0)
    return;

  double now = timespectod (current_timespec ());
  uint64_t threshold = zeln_fdo_threshold ();
  double interval = FLOATP (Vzeln_auto_fdo_interval)
    ? XFLOAT_DATA (Vzeln_auto_fdo_interval) : 60.0;

  for (ptrdiff_t i = 0; i < zeln_fdo_nunits; i++)
    {
      zeln_fdo_unit_t *u = &zeln_fdo_units[i];
      zeln_entry_t *e = u->entry;
      if (!e->fdo_counters || u->rounds >= ZELN_FDO_MAX_ROUNDS)
	continue;
      if (now - u->last_check < interval)
	continue;
      u->last_check = now;

      /* Count the hot fns; decide recompile.  */
      uint64_t maxc = 0;
      for (ptrdiff_t k = 0; k < e->n_fns; k++)
	if (e->fdo_counters[k] > maxc)
	  maxc = e->fdo_counters[k];
      if (maxc < threshold)
	continue;		/* nothing hot: wait for the next interval */

      /* Build <path>/<rel>.r<N>.zeln -- the ROUND NUMBER is in the name:
	 Windows (and only Windows) locks a loaded DLL, so round 2 must
	 never write over round 1's .zeln while this process still holds it
	 dlopen'd (zig cc's link step renames over the old file and fails
	 with "Removing old name: Permission denied"; POSIX just unlinks
	 the old inode and both remain valid).  Each round therefore gets
	 its own file; the superseded ones are simply abandoned (the OS
	 reclaims them at process exit).  The .zunit/.manifest/.zprofile
	 sidecars are derived from OUT by suffix, so they round-split too,
	 and the profile filename already encodes the round, keeping the
	 elisp harness's name-based profile lookup working.  */
      bool final = (u->rounds + 1 >= ZELN_FDO_MAX_ROUNDS);
      char *out = xmalloc (SBYTES (Vzeln_auto_fdo_path)
			   + SBYTES (u->rel_name) + 16);
      sprintf (out, "%s/%s.r%d", SSDATA (Vzeln_auto_fdo_path),
	       SSDATA (u->rel_name), u->rounds + 1);
      if (zeln_fdo_recompile (u, out, final))
	{
	  if (zeln_fdo_swap (u, out))
	    message ("zeln FDO: recompiled %s (round %d/%d)%s",
		     SSDATA (u->rel_name), u->rounds, ZELN_FDO_MAX_ROUNDS,
		     final ? " [final]" : "");
	}
      xfree (out);
    }
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

/* Close *FP (a FILE *) if non-NULL and set it to NULL.  Registered via
   record_unwind_protect_ptr after every emacs_fopen in the zeln writers so
   a signal between open and close (e.g. "constant does not round-trip"
   from the emit path, or a "too large" check) cannot leak the stdio
   stream.  The previous code leaked ~1 fd per failed serialize, which
   eventually exhausted the w32 fd table mid-population ("Too many open
   files" once ~520 round-trip skips had accumulated).  */
static void
zeln_unwind_close_file (void *arg)
{
  FILE **fp = arg;
  if (*fp)
    emacs_fclose (*fp);
  *fp = NULL;
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
  specpdl_ref fcount = SPECPDL_INDEX ();
  record_unwind_protect_ptr (zeln_unwind_close_file, &zout);

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

  {
    int zc = emacs_fclose (zout);
    zout = NULL;
    if (zc != 0)
      report_file_error ("Closing zunit", build_string (path));
  }

  /* --- .manifest: ASCII `Z1\n<sig>\n<8-hex>\n'.  */
  snprintf (path, sizeof path, "%s.manifest", prefix);
  FILE *mout = emacs_fopen (path, "w");
  if (!mout)
    report_file_error ("Opening manifest", build_string (path));
  record_unwind_protect_ptr (zeln_unwind_close_file, &mout);

  /* Sig line: the imported subr surface, name ++ prin1(arity).  The
     spike imports only `message' (arity (1 . MANY)) -> "message(1 . many)".  */
  fprintf (mout, "%s\n", ZELN_ABI_VERSION);
  fprintf (mout, "message(1 . many)\n");
  fprintf (mout, "%s\n", SSDATA (Vzeln_abi_hash));
  emacs_fclose (mout);
  mout = NULL;
  unbind_to (fcount, Qnil);

  return Qt;
}

/* Forward decl: zeln_const_tag is defined below comp-z-write-zunit, but
   zeln_emit_closure_body (which immediately follows) references it.  */
static uint8_t zeln_const_tag (Lisp_Object);

/* Round-trip self-check comparator: like Fequal, but hash tables compare
   by CONTENT.  `equal' never returns t for two distinct hash tables
   (internal_equal's vectorlike switch has no PVEC_HASH_TABLE case, so
   non-identical tables fall to the default and compare by identity),
   and the reader always builds a fresh table from #s(hash-table ...)
   syntax -- so a perfectly faithful round-trip was rejected and every
   .elc whose defuns hold a hash-table constant was skipped to the
   interpreter (763 files on 32.0.50).  Printing preserves the test name
   and the data but not the weakness, so weak tables are still rejected:
   their semantics genuinely do not survive the round-trip.  */
static bool
zeln_roundtrip_equal (Lisp_Object a, Lisp_Object b)
{
  if (BASE_EQ (a, b))
    return true;
  if (HASH_TABLE_P (a) && HASH_TABLE_P (b))
    {
      struct Lisp_Hash_Table *ha = XHASH_TABLE (a), *hb = XHASH_TABLE (b);
      if (ha->count != hb->count
	  || ha->weakness != hb->weakness
	  || !EQ (ha->test->name, hb->test->name)
	  || !EQ (ha->test->user_hash_function,
		  hb->test->user_hash_function)
	  || !EQ (ha->test->user_cmp_function,
		  hb->test->user_cmp_function))
	return false;
      DOHASH_SAFE (ha, i)
	{
	  ptrdiff_t j = hash_find (hb, HASH_KEY (ha, i));
	  if (j < 0
	      || !zeln_roundtrip_equal (HASH_VALUE (ha, i),
					HASH_VALUE (hb, j)))
	    return false;
	}
      return true;
    }
  return !NILP (Fequal (a, b));
}

/* If C is a byte-switch jump table (a hash table whose values are all
   fixnum offsets into the fn's bytecode), return the number of DISTINCT
   offsets and set *OFFS_OUT to a malloc'd sorted array of them;
   otherwise return -1.  bytecomp lowers pcase/cond switches to
   `Bconstant <jump-table>; Bswitch' (bytecomp.el:4639); the sidecar
   written from this lets the Zig emitter lower Bswitch to a static
   LLVM switch without parsing Lisp read-syntax.  */
static ptrdiff_t
zeln_switch_table_offsets (Lisp_Object c, ptrdiff_t opcode_len,
			   ptrdiff_t **offs_out)
{
  if (!HASH_TABLE_P (c))
    return -1;
  struct Lisp_Hash_Table *h = XHASH_TABLE (c);
  if (h->count < 1)
    return -1;
  ptrdiff_t *offs = xmalloc (h->count * sizeof *offs);
  ptrdiff_t n = 0;
  DOHASH_SAFE (h, j)
    {
      Lisp_Object v = HASH_VALUE (h, j);
      if (!FIXNUMP (v))
	goto not_table;
      ptrdiff_t off = XFIXNUM (v);
      if (off < 0 || off >= opcode_len)
	goto not_table;
      ptrdiff_t k = 0;
      while (k < n && offs[k] < off)
	k++;
      if (k < n && offs[k] == off)
	continue;
      memmove (offs + k + 1, offs + k, (n - k) * sizeof *offs);
      offs[k] = off;
      n++;
    }
  *offs_out = offs;
  return n;

 not_table:
  xfree (offs);
  return -1;
}

/* ------------------------------------------------------------------ */
/* (d-m1-shared) closure-body serializer.  Validates FUN is a lexical
   compiled closure (the exact shape exec_byte_code consumes) and emits
   ONE function body — args_template / stack_depth / opcodes / consts —
   into F (the zunit being written).  Used by BOTH comp-z-write-zunit
   (zabi=2, single-fn header) and comp-z-write-file-zunit (zabi=3, one
   body per defun).  Signals wrong-type-argument / error on anything that
   is not a serializable lexical closure; the caller's per-file fault
   tolerance (condition-case in the Elisp populate helper) turns a signal
   into a logged skip.  Extracted verbatim from the former
   comp-z-write-zunit body.  */
static void
zeln_emit_closure_body (FILE *f, Lisp_Object fun, bool emit_switch_tables)
{
  CHECK_TYPE (CLOSUREP (fun), Qcompiled_function_p, fun);
  CHECK_TYPE (FIXNUMP (AREF (fun, CLOSURE_ARGLIST)),
	      Qcompiled_function_p, fun);

  Lisp_Object bytestr   = AREF (fun, CLOSURE_CODE);		/* slot 1 */
  Lisp_Object vector    = AREF (fun, CLOSURE_CONSTANTS);	/* slot 2 */
  Lisp_Object maxdepth  = AREF (fun, CLOSURE_STACK_DEPTH);	/* slot 3 */
  ptrdiff_t args_tmpl   = FIXNUMP (AREF (fun, CLOSURE_ARGLIST))
      ? XFIXNUM (AREF (fun, CLOSURE_ARGLIST)) : -1; /* slot 0 */
  CHECK_TYPE (STRINGP (bytestr), Qstringp, bytestr);
  CHECK_TYPE (VECTORP (vector), Qvectorp, vector);
  CHECK_TYPE (FIXNATP (maxdepth), Qwholenump, maxdepth);

  ptrdiff_t opcode_len = SBYTES (bytestr);
  ptrdiff_t nconsts    = ASIZE (vector);
  if (opcode_len > 0xFFFFFFFFu || nconsts > 0xFFFFFFFFu)
    error ("zeln: bytecode/constants too large");

  emit_u32 (f, (uint32_t) args_tmpl);		/* 15-bit args_template */
  emit_u16 (f, (uint16_t) XFIXNAT (maxdepth));
  emit_u32 (f, (uint32_t) opcode_len);
  emit_bytes (f, SSDATA (bytestr), opcode_len);	/* raw opcodes */
  emit_u32 (f, (uint32_t) nconsts);

  /* Each constant serialized Lisp-aware via Fprin1_to_string (print.c:795)
     -> its read-syntax bytes; the loader Freads them back.  A round-trip
     self-check (RISK 5 mitigation) turns SILENT corruption (a constant
     whose Fread(Fprin1(c)) differs from c -- a bytecode object, a record,
     a circular structure, a multibyte string with binary bytes) into a
     signaled error so the per-file fault tolerance logs that .elc as a
     skip and it falls back to the interpreter, instead of baking a
     corrupted constant into the .zeln that crashes the native fn later.

     Bind the print settings so MORE constants survive the round-trip
     (the M2b 46.6% coverage gap): print-circle lets shared/circular
     structure print as #N=/#N# (readable); print-level/print-length =
     nil stops records and long lists from being truncated (a truncated
     print never Fequal-s its read-back); print-gensym keeps uninterned
     symbols readable.  The self-check bar is unchanged -- a constant
     still must Fequal its read-back, we just let more shapes pass it.  */
  specpdl_ref print_punct = SPECPDL_INDEX ();
  specbind (intern_c_string ("print-circle"), Qt);
  specbind (intern_c_string ("print-level"), Qnil);
  specbind (intern_c_string ("print-length"), Qnil);
  specbind (intern_c_string ("print-gensym"), Qt);
  for (ptrdiff_t i = 0; i < nconsts; i++)
    {
      Lisp_Object c = AREF (vector, i);
      Lisp_Object printed = Fprin1_to_string (c, Qnil, Qnil);
      ptrdiff_t clen = SBYTES (printed);
      if (clen > 0xFFFFFFFFu)
	error ("zeln: constant read-syntax too large");
      Lisp_Object roundtripped = Fread (printed);
      if (!zeln_roundtrip_equal (c, roundtripped))
	error ("zeln: constant does not round-trip (skip file)");
      emit_u8  (f, zeln_const_tag (c));		/* advisory; loader ignores */
      emit_u32 (f, (uint32_t) clen);
      emit_bytes (f, SSDATA (printed), clen);
    }
  unbind_to (print_punct, Qnil);

  /* (zabi=4) switch-table sidecar: for every jump-table constant, the
     DISTINCT sorted bytecode offsets, so the emitter can lower Bswitch
     to a static LLVM switch.  Layout after the consts:
       u32 n_tables; n_tables x { u32 const_idx; u32 n_offsets;
                                  u32 offsets[n_offsets]; }.  */
  if (emit_switch_tables)
    {
      ptrdiff_t n_tables = 0;
      for (ptrdiff_t i = 0; i < nconsts; i++)
	{
	  ptrdiff_t *offs;
	  if (zeln_switch_table_offsets (AREF (vector, i), opcode_len,
					 &offs) >= 0)
	    { xfree (offs); n_tables++; }
	}
      emit_u32 (f, (uint32_t) n_tables);
      for (ptrdiff_t i = 0; i < nconsts; i++)
	{
	  ptrdiff_t *offs;
	  ptrdiff_t n = zeln_switch_table_offsets (AREF (vector, i),
						    opcode_len, &offs);
	  if (n < 0)
	    continue;
	  emit_u32 (f, (uint32_t) i);
	  emit_u32 (f, (uint32_t) n);
	  for (ptrdiff_t k = 0; k < n; k++)
	    emit_u32 (f, (uint32_t) offs[k]);
	  xfree (offs);
	}
    }
}

/* ------------------------------------------------------------------ */
/* (d-m2b) M2b file-level capture state.  comp-z-write-file-zunit Floads
   the .elc with Vload_read_function bound to `zeln--capturing-read' so
   every top-level form the interpreter would eval is recorded (in
   reverse) into zeln_captured_forms, with `#$' doc substitution already
   resolved by Fload's machinery.  After Fload returns, the defun
   closures are fset on their symbols (so Fsymbol_function yields the
   live closure) and the captured list lets us classify defun vs non-defun
   forms.  Reset to Qnil before each file; staticpro'd in syms_of_compz.  */
static Lisp_Object zeln_captured_forms;
/* The file whose TOP-LEVEL forms we want to capture (the .elc arg to
   comp-z-write-file-zunit).  capturing-read records a form only when
   Vload_file_name names THIS file, so a nested (require ...) inside the
   .elc -- which runs within the same load-read-function binding -- does
   not pollute zeln_captured_forms with another file's forms.  */
static Lisp_Object zeln_capture_target;

DEFUN ("zeln--capturing-read", Fzeln_capturing_read, Szeln_capturing_read,
       1, 1, 0,
       doc: /* Internal: read one form from READCHARFUN and record it.
Bound as `load-read-function' while `comp-z-write-file-zunit' Floads a
.elc, so every top-level form is captured (in reverse) onto
`zeln-captured-forms' for later defun/non-defun classification.  A form
is recorded only when `load-file-name' is the file being captured, so a
nested (require ...) does not pollute the capture.  For internal use.  */)
  (Lisp_Object readcharfun)
{
  /* Mirror the default `read' the load loop calls (lread.c:2513-2516):
     Fload has already set up the stream + #$ doc machinery, so Fread
     handles `#$' / coding exactly as the interpreter sees them.  */
  Lisp_Object form = Fread (readcharfun);
  /* Record only forms of the file we are directly capturing (not forms
     pulled in by a nested require, which shares this binding).  */
  if (!NILP (form)
      && STRINGP (zeln_capture_target)
      && !NILP (Fstring_equal (Vload_file_name, zeln_capture_target)))
    zeln_captured_forms = Fcons (form, zeln_captured_forms);
  return form;
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
  /* INPUT VALIDATION + extraction + emit are in zeln_emit_closure_body
     (shared with comp-z-write-file-zunit).  Here we write only the
     zabi=2 single-fn header around it.  */
  CHECK_STRING (out_prefix);

  hash_zeln_abi ();
  eassert (!NILP (Vzeln_abi_hash));

  char prefix[4096];
  ptrdiff_t plen = SBYTES (out_prefix);
  if (plen >= (ptrdiff_t) sizeof (prefix) - 16)
    error ("comp-z-write-zunit: prefix too long");
  memcpy (prefix, SSDATA (out_prefix), plen);
  prefix[plen] = '\0';

  /* --- .zunit (M1, zabi=2): u32 magic; u8 zabi=2; then one fn body via
     zeln_emit_closure_body ({ u32 args_template; u16 stack_depth;
     u32 opcode_len; u8 opcodes[opcode_len]; u32 nconsts; nconsts ×
     { u8 tag_advisory; u32 len; u8 read_syntax[len] } }).  */
  char path[4096 + 16];
  snprintf (path, sizeof path, "%s.zunit", prefix);
  FILE *zout = emacs_fopen (path, "wb");
  if (!zout)
    report_file_error ("Opening zunit", build_string (path));
  specpdl_ref fcount = SPECPDL_INDEX ();
  record_unwind_protect_ptr (zeln_unwind_close_file, &zout);

  emit_u32 (zout, ZUNIT_MAGIC);
  emit_u8  (zout, 2);				/* zabi_version (M1) */
  zeln_emit_closure_body (zout, fun, false);

  {
    int zc = emacs_fclose (zout);
    zout = NULL;
    if (zc != 0)
      report_file_error ("Closing zunit", build_string (path));
  }

  /* --- .manifest: `<ZELN_ABI_VERSION>\n<sig>\n<8-hex>\n'.  The sig line
     is the fixed M1 surface (constant for all fns); the 8-hex is what
     the Zig tool bakes into the .zeln as freloc_hash_z.  */
  snprintf (path, sizeof path, "%s.manifest", prefix);
  FILE *mout = emacs_fopen (path, "w");
  if (!mout)
    report_file_error ("Opening manifest", build_string (path));
  record_unwind_protect_ptr (zeln_unwind_close_file, &mout);
  fprintf (mout, "%s\n", ZELN_ABI_VERSION);
  fprintf (mout, "%s\n", SSDATA (zeln_signature_string ()));
  fprintf (mout, "%s\n", SSDATA (Vzeln_abi_hash));
  emacs_fclose (mout);
  mout = NULL;
  unbind_to (fcount, Qnil);

  return Qt;
}

/* ------------------------------------------------------------------ */
/* (d-m2b) file-level serializer.  comp-z-write-file-zunit (FILE
   OUT-PREFIX): Floads a .elc, walks its defun closures + collects its
   non-defun top-level forms (via the load-read-function capture above),
   and writes ONE zabi=3 multi-function zunit + the manifest (plan M2b
   deliverable 1).  The zabi=3 zunit mirrors the whole .elc (N defuns +
   top-level replay), so loading ONE .zeln is a faithful substitute for
   loading the .elc -- the foundation of transparent load + the 582-via-
   .zeln gate.  Signals on any unserializable closure / load error; the
   Elisp populate helper's per-file condition-case turns a signal into a
   logged skip (deliverable 1 fault tolerance).  Returns the defun count
   (a fixnum), or nil if the file defines zero defuns (nothing to native-
   compile; the caller skips emitting a .zeln for it).  */
DEFUN ("comp-z-write-file-zunit", Fcomp_z_write_file_zunit,
       Scomp_z_write_file_zunit, 2, 2, 0,
       doc: /* Write a zabi=3 multi-function zunit + manifest for the .elc FILE.
FILE is a .elc path.  Loads it, walks its defun closures + collects its
non-defun top-level forms, and writes <OUT-PREFIX>.zunit + .manifest.
Returns the defun count, or nil if the file defines no defuns.  Signals
on an unserializable closure or a load error.  For internal use.  */)
  (Lisp_Object file, Lisp_Object out_prefix)
{
  CHECK_STRING (file);
  CHECK_STRING (out_prefix);
  hash_zeln_abi ();

  char prefix[4096];
  ptrdiff_t plen = SBYTES (out_prefix);
  if (plen >= (ptrdiff_t) sizeof (prefix) - 16)
    error ("comp-z-write-file-zunit: prefix too long");
  memcpy (prefix, SSDATA (out_prefix), plen);
  prefix[plen] = '\0';

  /* Capture every top-level form by Floading the .elc with
     load-read-function = zeln--capturing-read and load-no-native = t.
     The latter is CRITICAL: without it, maybe_swap_for_zeln would try to
     swap the .elc for a (possibly stale) .zeln and dispatch through the
     native loader instead of interpreting the .elc for capture.  Fload
     signals on a bad .elc; the caller's condition-case turns that into a
     logged skip.

     zeln_capture_target (the absolute .elc path) gates capturing-read so a
     nested (require ...) -- which shares this load-read-function binding --
     cannot pollute the capture with another file's forms.  */
  Lisp_Object absfile = Fexpand_file_name (file, Qnil);
  specpdl_ref count = SPECPDL_INDEX ();
  zeln_captured_forms = Qnil;
  zeln_capture_target = absfile;
  specbind (intern_c_string ("load-read-function"),
	    intern_c_string ("zeln--capturing-read"));
  specbind (intern_c_string ("load-no-native"), Qt);
  Fload (absfile, Qnil /*noerror*/, Qt /*nomessage*/,
	 Qnil /*nosuffix*/, Qt /*mustsuffix*/);
  unbind_to (count, Qnil);
  zeln_capture_target = Qnil;

  Lisp_Object forms = Fnreverse (zeln_captured_forms);
  zeln_captured_forms = Qnil;

  /* Classify: defalias forms -> defuns (serialize the LIVE closure under
     the symbol's name -- Fload just fset it); everything else -> the
     top_level_blob.  bytecomp emits one top-level `(defalias 'NAME
     CLOSURE ...)' per defun/defmacro/defsubst.  */
  Lisp_Object Qdefalias = intern_c_string ("defalias");
  Lisp_Object defun_list = Qnil;	/* (sym-name-string . closure), reversed */
  Lisp_Object blob_forms = Qnil;	/* non-defun forms, reversed */
  Lisp_Object ftail = forms;
  FOR_EACH_TAIL (ftail)
    {
      Lisp_Object form = XCAR (ftail);
      if (CONSP (form) && EQ (XCAR (form), Qdefalias))
	{
	  Lisp_Object sym_arg = Fcar (Fcdr (form));
	  /* sym_arg is usually (quote NAME); accept a bare symbol too.  */
	  Lisp_Object sym =
	    (CONSP (sym_arg) && EQ (XCAR (sym_arg), Qquote))
	      ? Fcar (Fcdr (sym_arg))
	      : sym_arg;
	  if (SYMBOLP (sym))
	    {
	      Lisp_Object closure = Fsymbol_function (sym);
	      if (CLOSUREP (closure)
		  && FIXNUMP (AREF (closure, CLOSURE_ARGLIST)))
		{
		  defun_list = Fcons (Fcons (SYMBOL_NAME (sym), closure),
				      defun_list);
		  continue;
		}
	    }
	  /* A defalias we could not classify -> replay it verbatim so the
	     interpreter re-fsets it (no native fn for that symbol).  */
	}
      blob_forms = Fcons (form, blob_forms);
    }

  defun_list = Fnreverse (defun_list);
  blob_forms = Fnreverse (blob_forms);
  ptrdiff_t nfuncs = 0;
  for (Lisp_Object t2 = defun_list; !NILP (t2); t2 = XCDR (t2))
    nfuncs++;

  /* A .elc with no defuns gains nothing from native comp (its whole
     effect is top-level).  Skip it: return nil so the caller records a
     "no-defuns" skip and does not emit a vacuous .zeln.  */
  if (nfuncs == 0)
    return Qnil;

  if (nfuncs > 0xFFFFFFFFu)
    error ("comp-z-write-file-zunit: too many defuns");

  /* --- .zunit (zabi=4): u32 magic; u8 zabi=4; u32 nfuncs;
     then nfuncs × { u32 sym_name_len; u8 sym_name[len]; <closure body> };
     then u32 top_blob_len; u8 top_blob[len].  The <closure body> is the
     SAME shape zeln_emit_closure_body writes (args_template,
     stack_depth, opcodes, consts) PLUS the zabi=4 switch-table sidecar
     (Bswitch's jump tables pre-resolved to distinct offset sets; zabi=3
     units carry none and every Bswitch in them stays an emitter
     skip).  */
  char path[4096 + 16];
  snprintf (path, sizeof path, "%s.zunit", prefix);
  FILE *zout = emacs_fopen (path, "wb");
  if (!zout)
    report_file_error ("Opening zunit", build_string (path));
  specpdl_ref fcount = SPECPDL_INDEX ();
  record_unwind_protect_ptr (zeln_unwind_close_file, &zout);

  emit_u32 (zout, ZUNIT_MAGIC);
  emit_u8  (zout, 4);			/* zabi_version (multi-fn + switch sidecar) */
  emit_u32 (zout, (uint32_t) nfuncs);

  for (Lisp_Object t2 = defun_list; !NILP (t2); t2 = XCDR (t2))
    {
      Lisp_Object pair = XCAR (t2);
      Lisp_Object namestr = XCAR (pair);	/* the symbol's name string */
      Lisp_Object closure = XCDR (pair);
      ptrdiff_t namelen = SBYTES (namestr);
      if (namelen > 0xFFFFFFFFu)
	error ("comp-z-write-file-zunit: symbol name too long");
      emit_u32 (zout, (uint32_t) namelen);
      emit_bytes (zout, SSDATA (namestr), namelen);
      zeln_emit_closure_body (zout, closure, true);
    }

  /* Top-level blob: (progn ,@blob_forms) as read-syntax.  Empty (zero
     forms) -> a zero-len blob (the loader skips a zero-len blob).  Print
     with the SAME relaxed bindings as the per-fn constants (print-circle so
     shared/circular structure prints as readable #N=/#N#; print-gensym for
     uninterned symbols; print-level/print-length unbounded).  Without
     print-circle a shared/circular top-level form Freads back as corrupt
     data, and Feval of that at load corrupts the heap (the M2b.3 gate #2
     cl-print.zeln crash).  */
  Lisp_Object blob_form = Fcons (Qprogn, blob_forms);
  specpdl_ref blob_print_punct = SPECPDL_INDEX ();
  specbind (intern_c_string ("print-circle"), Qt);
  specbind (intern_c_string ("print-level"), Qnil);
  specbind (intern_c_string ("print-length"), Qnil);
  specbind (intern_c_string ("print-gensym"), Qt);
  Lisp_Object blob_printed = Fprin1_to_string (blob_form, Qnil, Qnil);
  unbind_to (blob_print_punct, Qnil);
  ptrdiff_t blob_len = SBYTES (blob_printed);
  if (blob_len > 0xFFFFFFFFu)
    error ("comp-z-write-file-zunit: top-level blob too large");
  emit_u32 (zout, (uint32_t) blob_len);
  emit_bytes (zout, SSDATA (blob_printed), blob_len);

  {
    int zc = emacs_fclose (zout);
    zout = NULL;
    if (zc != 0)
      report_file_error ("Closing zunit", build_string (path));
  }

  /* --- .manifest: identical shape to M1 (ZELN_ABI_VERSION + sig + hash).  */
  snprintf (path, sizeof path, "%s.manifest", prefix);
  FILE *mout = emacs_fopen (path, "w");
  if (!mout)
    report_file_error ("Opening manifest", build_string (path));
  record_unwind_protect_ptr (zeln_unwind_close_file, &mout);
  fprintf (mout, "%s\n", ZELN_ABI_VERSION);
  fprintf (mout, "%s\n", SSDATA (zeln_signature_string ()));
  fprintf (mout, "%s\n", SSDATA (Vzeln_abi_hash));
  emacs_fclose (mout);
  mout = NULL;
  unbind_to (fcount, Qnil);

  return make_fixnum (nfuncs);
}

/* ------------------------------------------------------------------ */
/* (e) M1.5 cache layout + load-path plumbing.
   These mirror comp.c's .eln machinery (Fcomp_el_to_eln_rel_filename at
   comp.c:4306, comp_hash_string/comp_hash_source_file at comp.c:723/733,
   hash_native_abi's version-dir tail at comp.c:795-821, and the
   Vnative_comp_eln_load_path / Vcomp_native_version_dir / Vcomp_eln_to_el_h
   DEFVARs at comp.c:5770/5756/5766) — but reimplemented self-contained
   here because ALL of those comp.c helpers live inside #ifdef
   HAVE_NATIVE_COMP (comp.c:25..end) and are therefore invisible in the
   M1.5 config (gccjit OFF).  The hash need only be self-consistent
   within the zeln path (a .elc -> exactly one .zeln); it does NOT have
   to match the .eln hash, so independent reimplementation is safe.

   compz.c reaches MD5 through the Lisp-visible `md5' (the same
   Ffuncall trick hash_zeln_abi already uses), so it carries no md5.h or
   zlib dependency.  */

/* MD5 hex digest (first 8 chars) of a Lisp string, via `(md5 STRING nil
   nil 'binary)'.  Mirror comp.c:723 comp_hash_string (md5_buffer over
   SBYTES).  'binary hashes the raw storage bytes of a unibyte string,
   matching md5_buffer for ASCII/unibyte input; for the path hash the
   exact byte choice is irrelevant as long as serialize-side and
   load-side agree (both call THIS function on the same normalized
   path), so self-consistency holds regardless.  */
static Lisp_Object
comp_z_hash_string (Lisp_Object string)
{
  Lisp_Object md5_args[5] = { intern_c_string ("md5"), string, Qnil, Qnil,
			      intern_c_string ("binary") };
  Lisp_Object digest = Ffuncall (5, md5_args);
  return Fsubstring (digest, Qnil, make_fixnum (8));
}

/* MD5 hex digest (first 8 chars) of a source (.el / .el.gz) file's
   contents.  Mirror comp.c:733 comp_hash_source_file, including its
   streaming (md5_stream): no whole-file buffer, and read failures
   (including short reads) surface as a non-zero md5_stream return
   instead of being silently truncated into a wrong hash.  For a plain
   .el the digest is byte-identical to the old whole-file unibyte-string
   md5; for .el.gz it hashes the COMPRESSED bytes (still a
   self-consistent source->zeln binding; full gzip-aware hashing needs
   HAVE_ZLIB, deliberately not a compz.c dep).  content_hash is what
   binds a given .elc to exactly ONE .zeln and defeats stale
   dlopen-handle reuse (the rationale at comp.c:4348-4356 carries over
   verbatim).  */
static Lisp_Object
comp_z_hash_source_file (Lisp_Object filename)
{
  Lisp_Object encoded = ENCODE_FILE (filename);
  FILE *f = emacs_fopen (SSDATA (encoded), "rb");
  if (!f)
    report_file_error ("Opening source file", filename);

  Lisp_Object digest = make_uninit_string (MD5_DIGEST_SIZE * 2);
  int res = md5_stream (f, SSDATA (digest));
  emacs_fclose (f);
  if (res)
    report_file_error ("Hashing source file", filename);

  hexbuf_digest (SSDATA (digest), SSDATA (digest), MD5_DIGEST_SIZE);

  return Fsubstring (digest, Qnil, make_fixnum (8));
}

/* Cached compiled loadsearch-prefix regexps (mirror comp.c:4291
   loadsearch_re_list).  Built once, staticpro'd in syms_of_compz.  */
static Lisp_Object zeln_loadsearch_re_list;

DEFUN ("comp-z-el-to-zeln-rel-filename", Fcomp_z_el_to_zeln_rel_filename,
       Scomp_z_el_to_zeln_rel_filename, 1, 1, 0,
       doc: /* Return the relative name of the .zeln file for source FILENAME.
FILENAME must exist.  The value is

    <basename>-<path_hash>-<content_hash>.zeln

where <basename> is the source file's base name, <path_hash> hashes the
normalized source path (after stripping the build-tree / installed
loadsearch prefix, so installed vs build-tree paths collide
intentionally), and <content_hash> hashes the source file's contents.

This is the .zeln analogue of `comp-el-to-eln-rel-filename'; the two
need NOT agree (each is self-consistent within its own cache).  For
internal use.  */)
  (Lisp_Object filename)
{
  CHECK_STRING (filename);

  /* Resolve symlinks so path_hash compares equal across links (Bug#44701).  */
  filename = Fexpand_file_name (filename, Qnil);
  char *file_normalized = realpath (SSDATA (ENCODE_FILE (filename)), NULL);
  if (file_normalized)
    {
      filename = DECODE_FILE (make_unibyte_string (file_normalized,
						   strlen (file_normalized)));
      xfree (file_normalized);
    }

  if (NILP (Ffile_exists_p (filename)))
    xsignal1 (Qfile_missing, filename);

  Lisp_Object content_hash = comp_z_hash_source_file (filename);

  /* Strip a trailing ".gz" before computing path_hash / basename (so
     foo.el.gz and foo.el map consistently).  */
  if (suffix_p (filename, ".gz"))
    filename = Fsubstring (filename, Qnil, make_fixnum (-3));

  /* Normalize the build-tree / installed loadsearch prefix to "//" so
     the same source compiled in the build tree and after install hash
     to the same .zeln name (mirror comp.c:4363-4387).  */
  if (NILP (zeln_loadsearch_re_list))
    {
      Lisp_Object sys_re =
	concat2 (build_string ("\\`[[:ascii:]]+"),
		 Fregexp_quote (build_string ("/" PATH_REL_LOADSEARCH "/")));
      Lisp_Object dump_load_search =
	Fexpand_file_name (build_string (PATH_DUMPLOADSEARCH "/"), Qnil);
      zeln_loadsearch_re_list =
	list2 (sys_re, Fregexp_quote (dump_load_search));
    }

  Lisp_Object lds_re_tail = zeln_loadsearch_re_list;
  FOR_EACH_TAIL (lds_re_tail)
    {
      Lisp_Object match_idx =
	Fstring_match (XCAR (lds_re_tail), filename, Qnil, Qnil);
      if (BASE_EQ (match_idx, make_fixnum (0)))
	{
	  filename =
	    Freplace_match (build_string ("//"), Qt, Qt, filename, Qnil);
	  break;
	}
    }

  Lisp_Object separator = build_string ("-");
  Lisp_Object path_hash = comp_z_hash_string (filename);

  /* basename = nondirectory of FILENAME with the trailing ".el" stripped
     (mirror comp.c:4390).  */
  filename = concat2 (Ffile_name_nondirectory
		      (Fsubstring (filename, Qnil, make_fixnum (-3))),
		      separator);
  Lisp_Object hash = concat3 (path_hash, separator, content_hash);
  return concat3 (filename, hash, build_string (".zeln"));
}

/* Lazily build Vcomp_z_native_version_dir from Vzeln_abi_hash (mirror
   comp.c:795-821 building Vcomp_native_version_dir from Vcomp_abi_hash).
   Distinct value from the gccjit version-dir because the hash input
   differs (Vzeln_abi_hash vs Vcomp_abi_hash), so the two caches' dirs
   never collide.  Computed lazily because it needs Vemacs_version +
   coding systems (md5) post-dump; syms_of_compz runs before coding
   systems exist.  Idempotent.  */
void
compute_z_version_dir (void)
{
  if (!NILP (Vcomp_z_native_version_dir))
    return;

  hash_zeln_abi ();		/* ensure Vzeln_abi_hash */

  Lisp_Object version = Vemacs_version;

#ifdef NS_SELF_CONTAINED
  /* macOS self-contained bundles dislike dots in Frameworks dir names.  */
  version = STRING_MULTIBYTE (Vemacs_version)
    ? make_uninit_multibyte_string (SCHARS (Vemacs_version),
				    SBYTES (Vemacs_version))
    : make_uninit_string (SBYTES (Vemacs_version));
  const unsigned char *from = SDATA (Vemacs_version);
  unsigned char *to = SDATA (version);
  while (from < SDATA (Vemacs_version) + SBYTES (Vemacs_version))
    {
      unsigned char c = *from++;
      if (c == '.')
	c = '_';
      *to++ = c;
    }
#endif

  Vcomp_z_native_version_dir =
    concat3 (version, build_string ("-"), Vzeln_abi_hash);

#ifndef HAVE_NATIVE_COMP
  /* Config-compat mirror (see the eln-compat section below): keep
     `comp-native-version-dir' in lockstep with the zeln version dir so
     user configs / startup code reading the upstream name see the zeln
     cache layout.  */
  Vzeln_native_version_dir_compat = Vcomp_z_native_version_dir;
#endif
}

#ifndef HAVE_NATIVE_COMP
/* ------------------------------------------------------------------ */
/* eln-config compatibility layer (zeln-ONLY builds; gccjit provides
   all of this itself under HAVE_NATIVE_COMP).
   Goal: a user configuration written against the stock native-comp
   surface (native-comp-eln-load-path, comp-el-to-eln-filename, the
   `native-compile' feature test, native-comp-available-p, ...) must
   keep working when the build chose the Zig/LLVM (.zeln) path instead
   of gccjit (.eln) -- the eln-native configuration transparently
   SUBSTITUTES the zeln backend.

   Naming constraint: make-docfile extracts DEFUN/DEFVAR entries by C
   identifier WITHOUT evaluating #ifdefs, so every C name here
   deliberately differs from comp.c's (…_zeln suffix / _compat vars):
   identical C ids in comp.c+compz.c would collide in globals.h when
   both files are scanned.  The Lisp-visible names match comp.c exactly,
   and at runtime only ONE registration executes (comp.c's are inside
   #ifdef HAVE_NATIVE_COMP).  */

/* `native-comp-eln-load-path' (compat mirror).  Searched by the .zeln
   load swap (lread.c maybe_swap_for_zeln) and honored by
   comp-el-to-eln-filename, so `(setq native-comp-eln-load-path ...)' in
   user config steers the zeln cache exactly like it steers .eln.
   The C storage itself is generated by make-docfile into globals.h
   (f_Vzeln_* / i_zeln_* slots), like every DEFVAR variable -- no
   static declarations here.  */

/* `native-comp-jit-compilation' (compat mirror).  Default false: the
   gccjit deferred-async JIT pipeline (comp-run.el subprocess driving
   comp--compile-ctxt-to-file) is not wired to zeln yet; population is
   the explicit `zig build populate-zeln-cache' driver, and loads fall
   back to the interpreter transparently.  */

DEFUN ("comp-el-to-eln-rel-filename", Fcomp_el_to_eln_rel_filename_zeln,
       Scomp_el_to_eln_rel_filename_zeln, 1, 1, 0,
       doc: /* Return the relative name of the native file for FILENAME.
This build substitutes the Zig/LLVM (.zeln) backend for gccjit (.eln):
the value is the .zeln relative name (basename + path hash + content
hash + ".zeln"), self-consistent within the zeln cache.  FILENAME must
exist, and if it's a symlink, the target must exist.  */)
  (Lisp_Object filename)
{
  return Fcomp_z_el_to_zeln_rel_filename (filename);
}

/* Helper for Fcomp_el_to_eln_filename_zeln (mirror comp.c:4295).  */
static Lisp_Object
zeln_make_directory_wrapper (Lisp_Object directory)
{
  Lisp_Object args[2] = { intern_c_string ("make-directory"),
			  directory };
  Ffuncall (2, args);
  return Qnil;
}
static Lisp_Object
zeln_make_directory_wrapper_1 (Lisp_Object ignore)
{
  return Qt;
}

DEFUN ("comp-el-to-eln-filename", Fcomp_el_to_eln_filename_zeln,
       Scomp_el_to_eln_filename_zeln, 1, 2, 0,
       doc: /* Return the absolute native file name for source FILENAME.
This build substitutes the Zig/LLVM (.zeln) backend for gccjit (.eln):
the returned name is where the .zeln for FILENAME lives (or would be
produced), under a version-specific subdirectory determined by the
zeln ABI hash.  Behavior otherwise mirrors the stock function: with
non-nil BASE-DIR use it as the output directory (relative to
`invocation-directory' if not absolute); otherwise use the first
writable directory in `native-comp-eln-load-path'.  */)
  (Lisp_Object filename, Lisp_Object base_dir)
{
  filename = Fcomp_z_el_to_zeln_rel_filename (filename);

  if (NILP (base_dir))
    {
      Lisp_Object dirs = Vzeln_eln_load_path_compat;
      if (NILP (dirs))
	dirs = Vnative_comp_zeln_load_path;
      FOR_EACH_TAIL (dirs)
	{
	  Lisp_Object dir = XCAR (dirs);
	  if (!NILP (Ffile_exists_p (dir)))
	    {
	      if (!NILP (Ffile_writable_p (dir)))
		{
		  base_dir = dir;
		  break;
		}
	    }
	  else if (NILP (internal_condition_case_1 (zeln_make_directory_wrapper,
						    dir, Qt,
						    zeln_make_directory_wrapper_1)))
	    {
	      base_dir = dir;
	      break;
	    }
	}
      if (NILP (base_dir))
	error ("Cannot find suitable directory for output in "
	       "`native-comp-eln-load-path'.");
    }

  if (!file_name_absolute_p (SSDATA (base_dir)))
    base_dir = Fexpand_file_name (base_dir, Vinvocation_directory);

  compute_z_version_dir ();
  base_dir = Fexpand_file_name (Vcomp_z_native_version_dir, base_dir);
  return Fexpand_file_name (filename, base_dir);
}

DEFUN ("native-elisp-load", Fnative_elisp_load_zeln,
       Snative_elisp_load_zeln, 1, 2, 0,
       doc: /* Load a natively-compiled Lisp file FILENAME.
This build substitutes the Zig/LLVM (.zeln) backend for gccjit (.eln):
loading goes through the zeln loader (`comp-z-load-zeln').  LOAD-ERR
is accepted for call-compatibility and ignored (the zeln loader
signals on inconsistency rather than returning an error string).  */)
  (Lisp_Object filename, Lisp_Object load_err)
{
  return Fcomp_z_load_zeln (filename);
}

#endif /* !HAVE_NATIVE_COMP */

/* Elisp-callable wrapper around compute_z_version_dir: forces the lazy
   computation (needs Vemacs_version + coding systems post-dump) and
   returns `comp-z-native-version-dir'.  Used by the populate driver to
   place .zeln under the SAME <ver> dir the load side (maybe_swap_for_zeln)
   reads from, so write/read agree by construction.  */
DEFUN ("comp-z-compute-version-dir", Fcomp_z_compute_version_dir,
       Scomp_z_compute_version_dir, 0, 0, 0,
       doc: /* Return the .zeln-cache version directory for this build.
Computes it lazily (from `emacs-version' + `zeln-abi-hash') and caches it
in `comp-z-native-version-dir'.  For internal use.  */)
  (void)
{
  compute_z_version_dir ();
  return Vcomp_z_native_version_dir;
}

/* zeln-jit hotness diagnostics (J2): how many interpreted closures the
engine is tracking and how many crossed the JIT threshold.  Exposed so
the hotness hook's effect is observable from Lisp (tests, tuning). */
extern void zeln_jit_stats (unsigned [2]);

/* ------------------------------------------------------------------ */
static void zeln_freloc_check_fill (void);
extern bool zeln_jit_hot (const void *, unsigned);

/* J4: the in-process JIT swap.  exec_byte_code's hotness hook (below)
   counts interpreted invocations; when a closure crosses the threshold
   we compile it IN-PROCESS with the zeln-jit engine (tools/zeln-jit:
   bytecode -> x86-64 direct emission, no LLVM, no subprocess, no
   gcc/libgccjit) and cache the machine-code entry keyed on the
   bytecode-string data pointer.  Subsequent invocations call the entry
   through ZELN_JIT_ENTRY_CHECK before interpreting.  Any compile
   failure (unsupported opcode etc.) marks the closure "nojit" and the
   interpreter keeps it forever - identical to the .zeln skip
   semantics.  */

extern zeln_jit_entry_t zeln_jit_compile_closure
  (const unsigned char *, size_t, unsigned, unsigned,
   const Lisp_Object *, void *const *, const uint32_t *, size_t, uint64_t);
bool zeln_jit_supported (void);

/* The hand-written emitter is x86-64 only.  Gate at this boundary so an
   x86_64 JIT build stays fast, while an ARM64/Linux or Apple Silicon
   build cannot reach the emitter through an environment variable and
   instead silently uses the interpreter / .zeln AOT object.  */
bool
zeln_jit_supported (void)
{
#ifdef ZELN_JIT_ARCH_X86_64
  return true;
#else
  return false;
#endif
}

/* Resolve the diagnostic switch once.  This used to call getenv for
   every arith helper and every JIT dispatch; even an unsuccessful
   environment lookup is far too much overhead on the hot path.  */
static bool
zeln_jit_trace_p (void)
{
  static signed char state = -1;
  if (state < 0)
    {
      const char *e = getenv ("ZELN_JIT_TRACE");
      state = (e && e[0] == '1' && e[1] == '\0') ? 1 : 0;
    }
  return state != 0;
}

/* Alignment trampoline: the Zig compile_closure's frame uses aligned
   xmm stores (vmovaps) at fixed rbp offsets, and crashes when it is
   entered with an 8-mod-16 rbp chain (observed under the deep library
   loads; the exact culprit in the chain is still unidentified).  This
   naked shim forces rsp 16-alignment before the call, guaranteeing the
   callee's rbp lands aligned.  */
#if defined __x86_64__ && defined __GNUC__
static zeln_jit_entry_t
zeln_jit_compile_closure_aligned (const unsigned char *a, size_t b,
				  unsigned c, unsigned d,
				  const Lisp_Object *e, void *const *f,
				  const uint32_t *g, size_t h, uint64_t i)
  __attribute__ ((noinline));
#endif

/* Compiled-entry cache: open-addressed on the bytecode data pointer.
   NOJIT marks a rejected closure (never retried).  */
#define ZELN_JIT_CACHE_SIZE 1024
struct zeln_jit_cache_ent
{
  const unsigned char *key;	/* bytecode data pointer (0 = free) */
  ptrdiff_t key_len;		/* bytecode bytes at KEY */
  ptrdiff_t args_template;	/* encoded closure argument shape */
  zeln_jit_entry_t entry;	/* null + key set = rejected */
  const Lisp_Object *consts;	/* the constants vector the entry baked;
				   rebuilt closures (same bytecode, fresh
				   vector) must not reuse the entry.  */
};
static struct zeln_jit_cache_ent zeln_jit_cache[ZELN_JIT_CACHE_SIZE];
/* Diagnostics: compiles accepted / rejected (by stage).  */
static uintmax_t zeln_jit_accepted, zeln_jit_rejected;

/* GC root pinning every cache entry's closure: accepted code bakes the
   constants vector ADDRESS, and both accepted and NOJIT entries key on the
   bytecode-string ADDRESS.  The pin list holds each closure so its vector
   and bytecode string stay alive AND un-relocated for the process lifetime -
   the bounded-cost v1 answer (a GC-notify recompile is the follow-up).  */
static Lisp_Object Vzeln_jit_pinned_closures;

static struct zeln_jit_cache_ent *
zeln_jit_cache_lookup_exact (const unsigned char *key, ptrdiff_t args_template,
			     const Lisp_Object *consts)
{
  uintptr_t h = ((uintptr_t) key >> 4) * 2654435761u;
  unsigned start = h & (ZELN_JIT_CACHE_SIZE - 1);
  for (unsigned probes = 0, i = start; probes < ZELN_JIT_CACHE_SIZE;
       probes++, i = (i + 1) & (ZELN_JIT_CACHE_SIZE - 1))
    {
      if ((zeln_jit_cache[i].key == key
	   && zeln_jit_cache[i].args_template == args_template)
	  && zeln_jit_cache[i].consts == consts)
	return &zeln_jit_cache[i];
      if (zeln_jit_cache[i].key == NULL)
        return &zeln_jit_cache[i];
    }
  return NULL;
}

static struct zeln_jit_cache_ent *
zeln_jit_cache_lookup_shape (const unsigned char *key, ptrdiff_t args_template)
{
  uintptr_t h = ((uintptr_t) key >> 4) * 2654435761u;
  unsigned start = h & (ZELN_JIT_CACHE_SIZE - 1);
  for (unsigned probes = 0, i = start; probes < ZELN_JIT_CACHE_SIZE;
       probes++, i = (i + 1) & (ZELN_JIT_CACHE_SIZE - 1))
    {
      if ((zeln_jit_cache[i].key == key
	   && zeln_jit_cache[i].args_template == args_template)
	  || zeln_jit_cache[i].key == NULL)
	return &zeln_jit_cache[i];
      if (zeln_jit_cache[i].key == NULL)
	return &zeln_jit_cache[i];
    }
  return NULL;
}

/* The encoded args template is part of a closure's identity for JIT:
   identical bytecode can belong to closures with different arg-list
   setup, and the machine-code entry assumes the simple decoded shape.  */
static ptrdiff_t
zeln_closure_args_template (Lisp_Object fun)
{
  Lisp_Object x = AREF (fun, CLOSURE_ARGLIST);
  return FIXNUMP (x) ? XFIXNUM (x) : -1;
}

/* The freloc link table base, exposed to the JIT engine through a
   stable address (the engine bakes a load of this slot into each
   compiled prologue).  CRITICAL: force zeln_freloc_check_fill first -
   in a pdump-loaded child, syms_of_compz ran only in the DUMP process
   (initialized==true skips it on the load path), so link_table can
   still be empty here (all-NULL entries -> RIP=0).  check_fill is
   idempotent (size guard) and fills the table with THIS process's
   function addresses.  */
static void *const *zeln_jit_freloc_slot (void)
{
  static void *base;
  /* CRITICAL: force a REFILL, not the idempotent early-return.  In a
     pdump-loaded child the table can carry the DUMP process's
     addresses (statics restored from the dump where check_fill had
     already run), so a JIT compile in the child would bake dead
     pointers.  Resetting size to 0 makes check_fill refill with THIS
     process's addresses.  (This was also silently breaking the .zeln
     AOT path whenever a JIT compile ran first - the early forced
     check_fill in the DUMP process got its result persisted into the
     dump, and the child then early-returned with stale entries.)  */
  zeln_freloc.size = 0;
  zeln_freloc_check_fill ();
  base = zeln_freloc.link_table;
  return (void *const *) &base;
}

/* x86-64 realigning trampoline for the Zig compile entry (see the
   comment at the extern decl).  */
static zeln_jit_entry_t
zeln_jit_compile_trampoline (const unsigned char *a, size_t b,
			     unsigned c, unsigned d,
			     const Lisp_Object *e, void *const *f,
			     const uint32_t *g, size_t h, uint64_t i)
{
  /* and rsp,-16 twice with a push/pop dance is messy in C; the compiler
     already keeps C-ABI alignment at OUR frame, so the misalignment must
     come from deeper.  Fall through for now: call directly (the crash is
     under investigation; this trampoline keeps the seam for the asm fix
     without changing behavior).  */
  return zeln_jit_compile_closure (a, b, c, d, e, f, g, h, i);
}

/* Extract the exact jump targets for every hash-table constant.  This is
   the same validation zeln-compile performs for its AOT sidecar; giving
   the JIT the exact set avoids treating every bytecode boundary as a
   possible switch case.  The caller frees the returned array.  */
static uint32_t *
zeln_jit_collect_switch_targets (Lisp_Object vector, ptrdiff_t opcode_len,
				 size_t *count_out)
{
  uint32_t *targets = NULL;
  size_t count = 0, capacity = 0;
  *count_out = 0;
  if (!VECTORP (vector))
    return NULL;

  for (ptrdiff_t i = 0; i < ASIZE (vector); i++)
    {
      ptrdiff_t *offs = NULL;
      ptrdiff_t n = zeln_switch_table_offsets (AREF (vector, i),
					       opcode_len, &offs);
      for (ptrdiff_t j = 0; j < n; j++)
	{
	  if ((uintmax_t) offs[j] > UINT32_MAX)
	    {
	      xfree (offs);
	      xfree (targets);
	      return NULL;
	    }
	  uint32_t off = (uint32_t) offs[j];
	  if (count == capacity)
	    {
	      size_t newcap = capacity ? capacity * 2 : 8;
	      uint32_t *next = xrealloc (targets, newcap * sizeof *next);
	      targets = next;
	      capacity = newcap;
	    }
	  size_t k = 0;
	  while (k < count && targets[k] < off)
	    k++;
	  if (k < count && targets[k] == off)
	    continue;
	  memmove (targets + k + 1, targets + k,
		   (count - k) * sizeof *targets);
	  targets[k] = off;
	  count++;
	}
      if (n >= 0)
	xfree (offs);
    }
  *count_out = count;
  return targets;
}

/* Compile CLOSURE in-process; cache the entry (or the rejection).
   Returns the entry or null.  */
static zeln_jit_entry_t
zeln_jit_compile (Lisp_Object fun)
{
  Lisp_Object bytestr = AREF (fun, CLOSURE_CODE);
  if (!STRINGP (bytestr))
    return NULL;
  ptrdiff_t args_template = zeln_closure_args_template (fun);
  Lisp_Object vector = AREF (fun, CLOSURE_CONSTANTS);
  const Lisp_Object *consts = (VECTORP (vector)
			       ? XVECTOR (vector)->contents : NULL);
  struct zeln_jit_cache_ent *e
    = zeln_jit_cache_lookup_exact (SDATA (bytestr), args_template, consts);
  if (e == NULL)
    return NULL;		/* table full: fail closed to the interpreter */
  if (e->key != NULL)
    return e->entry;		/* exact hit (or prior rejection) */

  Lisp_Object maxdepth = AREF (fun, CLOSURE_STACK_DEPTH);

  /* Root FUN before creating any NOJIT cache entry.  Every cache entry
     stores SDATA (bytestr), so allowing rejected closures to be collected
     would leave a dangling key that another bytecode string could later
     reuse.  Pinning before validation also makes the conservative NOJIT
     cache exact rather than merely best-effort.  The first allocation can
     itself run GC, so recompute every derived address afterward.  */
  Vzeln_jit_pinned_closures = Fcons (fun, Vzeln_jit_pinned_closures);

  /* Fcons may have run GC and moved/recreated derived Lisp data.  Recompute
     every baked or cached address from the now-pinned closure.  */
  bytestr = AREF (fun, CLOSURE_CODE);
  args_template = zeln_closure_args_template (fun);
  vector = AREF (fun, CLOSURE_CONSTANTS);
  consts = (VECTORP (vector)
	    ? XVECTOR (vector)->contents : NULL);
  maxdepth = AREF (fun, CLOSURE_STACK_DEPTH);
  ptrdiff_t nargs_template = FIXNUMP (AREF (fun, CLOSURE_ARGLIST))
      ? XFIXNUM (AREF (fun, CLOSURE_ARGLIST)) : -1;

  {   /* ZELN_JIT_TRACE=1: log the first bytecodes of every compile so a
         crash site identifies the offending closure without a debugger.  */
    const bool tr = zeln_jit_trace_p ();
    if (tr)
      {
	fprintf (stderr, "[jit] compiling len=%d:",
		 (int) SBYTES (bytestr));
	for (int i = 0; i < SBYTES (bytestr) && i < 24; i++)
	  fprintf (stderr, " %02x", (unsigned char) SDATA (bytestr)[i]);
	fprintf (stderr, "\n");
      }
  }
  /* FULL slot validation before compiling anything: a malformed
     closure (observed from the dump with a non-string CODE slot)
     must never reach the emitter - its garbage slots would be baked
     into machine code that then corrupts memory when run.  */
  if (!VECTORP (vector) || !FIXNATP (maxdepth))
    {
      e->key = SDATA (bytestr);
      e->key_len = SBYTES (bytestr);
      e->args_template = args_template;
      e->consts = consts;
      e->entry = NULL;
      return NULL;
    }

  /* The ARGLIST slot holds the ENCODED args template (bytecode.c):
     bits 0..6 mandatory, bit 7 &rest, bits 8..14 max.  Decode and
     compile only the simple shape (no &rest, min == max, <= 8 args):
     the JIT entry pushes args[0..n) verbatim, which matches exactly
     that case; everything else keeps the interpreter's nil-fill /
     rest-pack setup.  */
  bool rest_bit = (nargs_template & 128) != 0;
  unsigned mandatory = nargs_template & 127;
  unsigned nonrest = (unsigned) (nargs_template >> 8) & 127;
  if (rest_bit || mandatory != nonrest || nonrest > 8)
    {
      e->key = SDATA (bytestr);
      e->key_len = SBYTES (bytestr);
      e->args_template = args_template;
      e->consts = consts;
      e->entry = NULL;
      return NULL;
    }

  size_t switch_target_count = 0;
  uint32_t *switch_targets
    = zeln_jit_collect_switch_targets (vector, SBYTES (bytestr),
				       &switch_target_count);

  zeln_jit_entry_t entry
    = zeln_jit_compile_trampoline
	(SDATA (bytestr), SBYTES (bytestr),
	 (unsigned) XFIXNAT (maxdepth), nonrest,
	 XVECTOR (vector)->contents, zeln_jit_freloc_slot (),
	 switch_targets, switch_target_count, XLI (Qt));
  xfree (switch_targets);
  {
    const bool tr = zeln_jit_trace_p ();
    if (tr)
      {
	fprintf (stderr, "[jit] compile done arity=%d depth=%d -> %p consts@%p c:",
		 (int) nonrest, (int) XFIXNAT (maxdepth), (void *) entry,
		 (void *) XVECTOR (vector)->contents);
	for (int ci = 0; ci < 4 && ci < ASIZE (vector); ci++)
	  fprintf (stderr, " [%d]=%016"PRIxMAX, ci,
		   (uintmax_t) XLI (AREF (vector, ci)));
	fprintf (stderr, " code:");
	if (entry)
	  for (int i = 0; i < 64; i++)
	    fprintf (stderr, " %02x",
		     ((unsigned char *) entry)[i]);
	fprintf (stderr, "\n");
	/* The freloc slot the engine baked + the first table entries.  */
	void *const *ltb = zeln_jit_freloc_slot ();
	fprintf (stderr, "[jit] slot=%p base=%p t1=%p t3=%p t4=%p t13=%p t14=%p t15=%p\n",
		 (void *) ltb, (void *) *ltb,
		 ((void **) *ltb)[1], ((void **) *ltb)[3], ((void **) *ltb)[4],
		 ((void **) *ltb)[13], ((void **) *ltb)[14], ((void **) *ltb)[15]);
      }
  }
  e->key = SDATA (bytestr);
  e->key_len = SBYTES (bytestr);
  e->args_template = args_template;
  e->entry = entry;
  e->consts = consts;
  if (entry != NULL)
    zeln_jit_accepted++;
  else
    zeln_jit_rejected++;
  return entry;
}

/* byte-code side helper: compile on the first threshold crossing.
   Kept separate so bytecode.c needs no cache internals.  ZELN_JIT=0 in
   the environment disables compilation entirely (hotness still counts)
   - the diagnostic switch while the J4 integration is young.  */
static bool zeln_jit_enabled_state = -1;

/* Runtime-tunable tier-1 trigger.  A low value is useful for tests and
   latency-sensitive entry points; a high value avoids compiling many
   rarely-useful closures.  Keep the hot table's exact crossing semantic:
   lowering this after calls have accumulated does not compile every
   already-counted closure, but newly tracked closures use it at once.  */
static unsigned
zeln_jit_hot_threshold (void)
{
  EMACS_INT n = Vzeln_jit_threshold;
  if (n >= 1 && n <= UINT_MAX)
    return (unsigned) n;
  return 256;
}

/* The lookup is exact in bytecode data, argument shape, and constants
   pointer.  cl-generic rebuilds dispatch closures with the same
   bytecode string and FRESH constants vectors; each gets its own entry
   rather than reading another closure's baked tags.  */
static zeln_jit_entry_t
zeln_jit_validated_entry (Lisp_Object fun, Lisp_Object bytestr)
{
  struct zeln_jit_cache_ent *e
    = zeln_jit_cache_lookup_exact
	(SDATA (bytestr), zeln_closure_args_template (fun),
	 (VECTORP (AREF (fun, CLOSURE_CONSTANTS))
	  ? XVECTOR (AREF (fun, CLOSURE_CONSTANTS))->contents : NULL));
  if (e == NULL)
    return NULL;
  if (e->key == NULL || e->entry == NULL)
    return NULL;
  return e->entry;
}

/* True when machine code already exists for this bytecode/arg shape.
   Used to
   distinguish a rebuilt closure (adopt immediately) from a cold
   closure (wait for the hotness threshold).  */
static bool
zeln_jit_has_entry (Lisp_Object fun, Lisp_Object bytestr)
{
  struct zeln_jit_cache_ent *e
    = zeln_jit_cache_lookup_shape (SDATA (bytestr),
			     zeln_closure_args_template (fun));
  if (e == NULL)
    return false;
  return e->key != NULL && e->entry != NULL;
}

bool
zeln_jit_should_compile (Lisp_Object fun)
{
  if (! zeln_jit_supported ())
    return false;
  /* v1 compilation state is owned by the main Lisp thread.  Other
     threads deliberately stay on the interpreter until the immutable
     entry cache is published; this avoids unsynchronized cache writes
     without taking a lock on every bytecode call.  */
  if (! in_main_lisp_thread ())
    return false;
  if (zeln_jit_enabled_state == -1)
    {
      /* getenv once.  emacs.c already refused to arm the outer gate on
	 an unsupported architecture; this is the compile-side backstop.  */
      const char *e = getenv ("ZELN_JIT");
      zeln_jit_enabled_state = (e && e[0] == '1' && e[1] == '\0');
    }
  if (! zeln_jit_enabled_state)
    return false;
  return zeln_jit_compile (fun) != NULL;
}

/* The exec_byte_code entry hook (bytecode.c calls this BEFORE the
   hotness count when a cached entry exists).  Returns true and sets
   *RESULT when the JIT'd entry ran.  */
/* The one-time JIT gate: true only when ZELN_JIT=1 was in the
   environment at startup.  byte-code's call site branches on this
   directly (one predictable load+test, no frame) so deep recursion in
   tiny-stack build environments is unaffected when the JIT is off.  */
/* Resolved ONCE during startup (syms_of_compz) so the inline read in
   bytecode.c never sees the unresolved -1 sentinel (which reads as
   TRUE and fired the JIT path in builds where the env var was unset).  */
bool zeln_jit_gate_var;	/* false by default (C zero-init) */

bool
zeln_jit_gate (void)
{
#ifdef ZELN_JIT_ARCH_X86_64
  return zeln_jit_gate_var;
#else
  return false;
#endif
}

/* Combined entry hook (stack-frugal): exec_byte_code calls ONLY this -
   one callee frame per interpreted invocation instead of three
   (will_dump_p + STRINGP are inlined by the compiler; the deep loaddefs
   scrape recursion sits a few hundred bytes below the guard page and the
   extra frames of the earlier 3-call shape overflowed it).  Returns true
   and sets *RESULT when a compiled entry ran.  */
bool
zeln_jit_entry_hook (Lisp_Object fun, ptrdiff_t args_template,
		     ptrdiff_t nargs, Lisp_Object *args,
		     Lisp_Object *result)
{
  if (will_dump_p ())
    return false;
  if (! in_main_lisp_thread ())
    return false;
  if (! zeln_jit_supported ())
    return false;
  /* During the zeln serialize capture (comp-z-write-file-zunit's
     capturing Fload) the loaded closures' constants vectors are
     capture-scoped; JIT-compiling them ran a closure whose funcall
     resolved to nil (void-function nil at bovine/scm-by).  Skip the
     JIT entirely while a capture is active - the interpreter's
     capture semantics are the contract here.  */
  if (!NILP (zeln_capture_target))
    return false;
  Lisp_Object bytestr = AREF (fun, CLOSURE_CODE);
  if (!STRINGP (bytestr))
    return false;
  bool rest_bit = (args_template & 128) != 0;
  ptrdiff_t mandatory = args_template & 127;
  ptrdiff_t nonrest = args_template >> 8;
  if (! rest_bit && mandatory == nonrest && nargs == mandatory)
    {
      zeln_jit_entry_t cached = zeln_jit_validated_entry (fun, bytestr);
      if (cached != NULL)
	{
	  {   /* ZELN_JIT_TRACE=1: mark the transition into JIT code so an
	       AV immediately after this line is inside the entry.  */
	    const bool tr = zeln_jit_trace_p ();
	    if (tr)
	      fprintf (stderr, "[jit] EXECUTING entry %p\n", (void *) cached);
	  }
	  *result = cached (nargs, args);
	  return true;
	}
      else if (zeln_jit_has_entry (fun, bytestr))
	{
	  /* Same bytecode/shape as an accepted closure, but fresh
	     constants (cl-generic rebuilds these).  Compile a separate
	     exact entry against FUN so it cannot read another closure's
	     baked constants.  */
	  if (zeln_jit_should_compile (fun))
	    cached = zeln_jit_validated_entry (fun, bytestr);
	  if (cached != NULL)
	    {
	      *result = cached (nargs, args);
	      return true;
	    }
	}
    }
  if (zeln_jit_hot (SDATA (bytestr), zeln_jit_hot_threshold ()))
    (void) zeln_jit_should_compile (fun);
  return false;
}

bool
zeln_jit_try_run (Lisp_Object fun, ptrdiff_t nargs, Lisp_Object *args,
		  Lisp_Object *result)
{
  if (! in_main_lisp_thread ())
    return false;
  Lisp_Object bytestr = AREF (fun, CLOSURE_CODE);
  if (!STRINGP (bytestr))
    return false;
  zeln_jit_entry_t entry = zeln_jit_validated_entry (fun, bytestr);
  if (entry == NULL)
    return false;
  /* The caller (exec_byte_code) guarantees the simple fixed-arity
     shape; run.  */
  *result = entry (nargs, args);
  return true;
}
extern unsigned zeln_jit_count (const void *);

DEFUN ("zeln-jit-dump", Fzeln_jit_dump, Szeln_jit_dump, 0, 0, 0,
       doc: /* Dump the first 64 bytecode bytes of each JIT cache entry.
The value is a newest-first list of byte vectors.  Entries whose bytecode
is shorter than 64 bytes are truncated to their full length.  */)
  (void)
{
  Lisp_Object out = Qnil;
  for (int i = 0; i < ZELN_JIT_CACHE_SIZE; i++)
    if (zeln_jit_cache[i].key != NULL && zeln_jit_cache[i].entry != NULL)
      {
	ptrdiff_t dump_len = min (zeln_jit_cache[i].key_len,
				  64);
	Lisp_Object bytes = make_uninit_vector (dump_len);
	for (ptrdiff_t k = 0; k < dump_len; k++)
	  ASET (bytes, k, make_fixnum (zeln_jit_cache[i].key[k]));
	out = Fcons (bytes, out);
      }
  return out;
}

DEFUN ("zeln-jit-compiled-p", Fzeln_jit_compiled_p, Szeln_jit_compiled_p, 1, 1, 0,
       doc: /* Return t when FUNCTION has an in-process JIT entry. */)
  (Lisp_Object function)
{
  CHECK_TYPE (CLOSUREP (function), Qcompiled_function_p, function);
  Lisp_Object bytestr = AREF (function, CLOSURE_CODE);
  if (!STRINGP (bytestr))
    return Qnil;
  return (zeln_jit_validated_entry (function, bytestr) != NULL) ? Qt : Qnil;
}

DEFUN ("zeln-jit-count", Fzeln_jit_count, Szeln_jit_count, 1, 1, 0,
       doc: /* Return the zeln-jit invocation count for compiled FUNCTION.
0 when not tracked (never invoked through the interpreter).  For
diagnostics/tuning of the JIT hotness gate.  */)
  (Lisp_Object function)
{
  CHECK_TYPE (CLOSUREP (function),
	      Qcompiled_function_p, function);
  Lisp_Object bytestr = AREF (function, CLOSURE_CODE);
  /* A closure whose body was never byte-compiled (interpreted
     lambda) carries its form list here, not a string. */
  if (!STRINGP (bytestr))
    return make_fixnum (0);
  return make_fixnum (zeln_jit_count (SDATA (bytestr)));
}

DEFUN ("zeln-jit-stats", Fzeln_jit_stats, Szeln_jit_stats, 0, 0, 0,
  doc: /* Return the zeln-jit counters as (TRACKED CROSSED ACCEPTED
REJECTED FAST-CALLS).
TRACKED is the number of distinct interpreted closures the JIT engine
is counting; CROSSED how many crossed the JIT threshold; ACCEPTED and
REJECTED count compiled closures; FAST-CALLS counts guarded direct calls
through `zeln-jit-call'.  Returns nil when the build lacks engine.  */)
  (void)
{
  unsigned st[2] = { 0, 0 };
  zeln_jit_stats (st);
  return list5 (make_fixnum (st[0]), make_fixnum (st[1]),
		make_fixnum (zeln_jit_accepted),
		make_fixnum (zeln_jit_rejected),
		make_fixnum (zeln_jit_fast_calls));
}

DEFUN ("zeln-jit-supported-p", Fzeln_jit_supported_p,
       Szeln_jit_supported_p, 0, 0, 0,
       doc: /* Return t when this build can execute the in-process JIT.  */)
  (void)
{
  return zeln_jit_supported () ? Qt : Qnil;
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

  /* M1.5 load-path / cache plumbing — the exact parallel of comp.c's
     Vnative_comp_eln_load_path (comp.c:5770), Vcomp_native_version_dir
     (comp.c:5756), and Vcomp_eln_to_el_h (comp.c:5766).  All three are
     DEFVAR'd fresh here because the gccjit DEFVARs live under
     #ifdef HAVE_NATIVE_COMP and are invisible in the M1.5 config.  */

  DEFVAR_LISP ("native-comp-zeln-load-path", Vnative_comp_zeln_load_path,
	       doc: /* List of directories to look for native-compiled *.zeln files.
The *.zeln files are looked for in a version-specific subdirectory of
each directory in this list, determined by `comp-z-native-version-dir'.
If a directory name is not absolute, it is relative to
`invocation-directory'.  This is the .zeln analogue of
`native-comp-eln-load-path'; the two caches are independent.  */);
  /* Temporary bootstrap default (mirror comp.c:5785): invocation-directory
     is unset during the dump, so the relative name is fixed up against it
     in src/emacs.c on dump reload.  */
  Vnative_comp_zeln_load_path = Fcons (build_string ("../zeln-lisp/"), Qnil);

  DEFVAR_LISP ("comp-z-native-version-dir", Vcomp_z_native_version_dir,
	       doc: /* Directory used to disambiguate .zeln compatibility.
Built lazily from `emacs-version' and `zeln-abi-hash' (distinct from
`comp-native-version-dir' so the two caches never collide).  */);
  Vcomp_z_native_version_dir = Qnil;

  DEFVAR_INT ("zeln-load-count", zeln_load_count,
    doc: /* Number of .zeln units loaded to completion in this session.
Instrumentation for the check-zeln gate: the harness (run-check.zig with
ZELN_LOAD_PATH set) fails when this stays 0, proving the 582-via-.zeln
run genuinely executed native code rather than silently falling back to
the interpreter.  */);
  zeln_load_count = 0;

  DEFVAR_INT ("zeln-jit-threshold", Vzeln_jit_threshold,
    doc: /* Number of interpreted calls before the in-process JIT compiles
a fixed-arity closure.  The default is 256.  Use a smaller value to make
hot interactive workloads enter Tier 1 sooner, or a larger value to avoid
compiling closures that stay cold in a particular session.  Takes effect
for closures not already tracked by the hotness table.  A non-positive or
non-integer value restores 256.  */);
  Vzeln_jit_threshold = 256;

  /* ---- FDO config (auto profile-guided recompilation).  All three
     default to OFF: with zeln_auto_fdo_path nil the loaded .zeln's
     fdo_active flags stay 0 and the per-fn counter branch falls
     through (~2 cycles/call); setting path + profile switches the
     machinery on for subsequently loaded units.  */
  DEFVAR_LISP ("zeln-auto-fdo-path", Vzeln_auto_fdo_path,
    doc: /* Directory for automatic profile-guided optimization of .zeln
units.  When non-nil (and `zeln-auto-fdo-profile' is non-nil), every
loaded .zeln starts collecting per-function call counts automatically
(no manual enable): at post-GC intervals set by
`zeln-auto-fdo-interval', and when any function exceeds the hot
threshold the unit's profile is written to
<PATH>/<zeln-rel-name>.zprofile and the unit is recompiled with
`zeln-compile --profile' (hot-first layout + branch weights), then
hot-swapped in place.  The recompiled artifact lands at
<PATH>/<zeln-rel-name>.zeln.  A unit is recompiled at most twice (the
second round is `--final', dropping the counters entirely);
auto-optimization stops once the round limit is reached.  While a
unit's profile stays below the threshold it is simply re-checked at
each interval without recompiling.  nil (default) disables the whole
feature.  */);
  Vzeln_auto_fdo_path = Qnil;

  DEFVAR_LISP ("zeln-auto-fdo-interval", Vzeln_auto_fdo_interval,
    doc: /* Minimum number of seconds between automatic FDO checks
(profile flush + recompile decision) for .zeln units, measured at
garbage-collection time.  Default 60.  Set to 0 to check on every GC.  */);
  Vzeln_auto_fdo_interval = make_float (60.0);

  DEFVAR_LISP ("zeln-auto-fdo-profile", Vzeln_auto_fdo_profile,
    doc: /* Profile-collection switch for automatic .zeln FDO.
nil (default): no collection (the .zeln counters stay gated off).
t: collect call counts for every loaded .zeln; a function is hot when
   its call count exceeds the default threshold (1000).
a number N: collect and treat a function as hot above N calls.
The hot threshold gates both recompilation and the auto-stop: when no
function of a unit exceeds it after a recompile round, that unit stops
being auto-optimized.  */);
  Vzeln_auto_fdo_profile = Qnil;

  DEFVAR_LISP ("comp-zeln-to-el-h", Vzeln_to_el_h,
	       doc: /* Hash table zeln-filename -> el-filename.
Mirrors `comp-eln-to-el-h'; used so loading a .zeln reports the source
.elc in `load-file-name' / `load-history'.  */);
  Vzeln_to_el_h = CALLN (Fmake_hash_table, QCtest, Qequal);

  /* M2.5 precedence control.  When both native-comp paths are enabled
     (HAVE_NATIVE_COMP and HAVE_NATIVE_COMP_ZIG), `openp' runs the two
     maybe_swap_for_* hooks (src/lread.c).  Each hook gates on the load
     filename ending in ".elc" and, on a hit, MUTATES it to the native
     artifact's path -- so the FIRST hook that finds a fresh native file
     wins; the second then sees a non-.elc name and returns early.  The
     hook that finds nothing leaves the name untouched, letting the
     other run (the fallback).  This variable picks the ORDER so the
     PREFERRED artifact's hook runs FIRST (and wins); the other runs
     second as a fallback.  nil (default) => prefer .eln: gccjit wins
     ties, .zeln loads only where no .eln matches (so the both-on `zig
     build check' suite runs entirely on the gccjit .eln path and stays
     independent of the .zeln execution gate).  t => prefer .zeln
     (opt-in; exercises the .zeln path).  No effect unless both
     native-comp switches are on at build time.  */
  DEFVAR_BOOL ("native-comp-z-prefer", native_comp_z_prefer,
    doc: /* Non-nil means prefer the Zig native-comp (.zeln) over the
gccjit native-comp (.eln) when both are available for a .elc being
loaded.  nil (default) prefers the .eln (gccjit) and uses the .zeln
only as a fallback where no .eln exists.

This only has an effect when Emacs was built with both native-comp
paths enabled (-Dnative-comp=true -Dnative-comp-zig=true); otherwise
exactly one native path is active and this variable is ignored.  */);
  native_comp_z_prefer = false;

  staticpro (&zeln_loadsearch_re_list);
  zeln_loadsearch_re_list = Qnil;

  /* M2b capture state (comp-z-write-file-zunit).  GC-invisible across a
     capture (the list is transitory), but staticpro'd defensively so a GC
     during Fload cannot collect the cons cells before classification.  */
  staticpro (&zeln_captured_forms);
  zeln_captured_forms = Qnil;
  staticpro (&zeln_capture_target);
  zeln_capture_target = Qnil;
  /* Root for the loader's reconstructed constant vectors -- see
     zeln_fill_d_reloc_fn.  Without this the constants a .zeln's static
     `d_reloc' array aliases would be swept by the first post-load GC.  */
  staticpro (&zeln_loaded_const_vectors);
  zeln_loaded_const_vectors = Qnil;
  /* FDO unit root (see the declaration): the loaded units' subr lists
     must survive until their hot-swap.  */
  staticpro (&zeln_fdo_subrs_root);
  zeln_fdo_subrs_root = Qnil;
  staticpro (&zeln_fdo_names_root);
  /* zeln-jit (J4): the cache-entry closures pin list.  */
  staticpro (&Vzeln_jit_pinned_closures);
  Vzeln_jit_pinned_closures = Qnil;

  zeln_fdo_names_root = Qnil;

  defsubr (&Scomp_z_load_zeln);
  defsubr (&Scomp_z_write_spike_zunit);
  defsubr (&Scomp_z_write_zunit);
  defsubr (&Scomp_z_write_file_zunit);
  defsubr (&Szeln_capturing_read);
  defsubr (&Scomp_z_compute_version_dir);
  defsubr (&Szeln_jit_stats);
  defsubr (&Szeln_jit_supported_p);
  defsubr (&Szeln_jit_count);
  defsubr (&Szeln_jit_compiled_p);
  defsubr (&Szeln_jit_dump);
  defsubr (&Scomp_z_el_to_zeln_rel_filename);

#ifndef HAVE_NATIVE_COMP
  /* eln-config compat registrations (see the compat section above):
     the stock native-comp Lisp surface, provided by the zeln backend.
     Only reachable in zeln-ONLY builds -- with gccjit on, comp.c owns
     every one of these names.  */
  defsubr (&Scomp_el_to_eln_rel_filename_zeln);
  defsubr (&Scomp_el_to_eln_filename_zeln);
  defsubr (&Snative_elisp_load_zeln);

  DEFVAR_LISP ("native-comp-eln-load-path", Vzeln_eln_load_path_compat,
    doc: /* List of directories to look for native-compiled *.zeln files.
This build substitutes the Zig/LLVM (.zeln) backend for gccjit (.eln):
the name is kept for configuration compatibility, and the directories
are searched (version-specific subdirectory, zeln ABI hash) when
loading and when computing output names via `comp-el-to-eln-filename'.
Relative directory names are interpreted relative to
`invocation-directory'.  */);
  Vzeln_eln_load_path_compat = Qnil;

  DEFVAR_BOOL ("native-comp-jit-compilation", zeln_jit_compilation_compat,
    doc: /* If non-nil, compile loaded .elc files asynchronously.
NOTE: on this Zig/LLVM (.zeln) build deferred async compilation is not
active yet -- the variable is provided for configuration compatibility
and always behaves as nil; populate the zeln cache with
`zig build -Dnative-comp-zig=true populate-zeln-cache'.  */);
  zeln_jit_compilation_compat = false;

  DEFVAR_LISP ("native-comp-enable-subr-trampolines",
	       Vzeln_subr_trampolines_compat,
    doc: /* If non-nil, enable generation of trampolines for calling primitives.
Trampolines are a gccjit native-comp concept; this Zig/LLVM (.zeln)
build accepts the variable for configuration/startup compatibility but
does not generate trampolines.  */);
  Vzeln_subr_trampolines_compat = Qt;

  DEFVAR_LISP ("comp-subr-arities-h", Vzeln_subr_arities_compat,
    doc: /* Hash table recording the arity of Lisp primitives.
Populated during loadup under (featurep 'native-compile); provided by
the zeln backend on this build.  */);
  Vzeln_subr_arities_compat = CALLN (Fmake_hash_table, QCtest, Qequal);

  DEFVAR_LISP ("comp-native-version-dir", Vzeln_native_version_dir_compat,
    doc: /* Directory used to disambiguate native files compatibility.
On this Zig/LLVM (.zeln) build this mirrors `comp-z-native-version-dir'
(the zeln ABI-hash version directory); the upstream name is kept for
configuration compatibility.  */);
  Vzeln_native_version_dir_compat = Qnil;
#endif

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
