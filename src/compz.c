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

#include <stdlib.h>		/* realpath, intptr_t */
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

   ZELN_ABI_VERSION was bumped Z1 -> Z2 for the M1 layout + surface,
   then Z2 -> Z3 for the M2 freloc-surface growth, so a stale M0/M1
   .zeln is rejected by the hash gate before any native code runs.  */

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
     mirroring comp.c:787-793.  ZELN_ABI_VERSION ("Z3" for M2; "Z2"
     covered M1, "Z1" M0) is the
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
   contents.  Mirror comp.c:733 comp_hash_source_file.  comp.c streams
   through md5_stream (and md5_gz_stream under HAVE_ZLIB); compz.c reads
   the whole file into a unibyte string and md5s it.  For plain .el this
   is byte-identical to comp.c; for .el.gz it hashes the COMPRESSED
   bytes (still a self-consistent source->zeln binding; full gzip-aware
   hashing is M2 — it needs HAVE_ZLIB, deliberately not a compz.c dep).
   content_hash is what binds a given .elc to exactly ONE .zeln and
   defeats stale dlopen-handle reuse (the rationale at comp.c:4348-4356
   carries over verbatim).  */
static Lisp_Object
comp_z_hash_source_file (Lisp_Object filename)
{
  Lisp_Object encoded = ENCODE_FILE (filename);
  FILE *f = emacs_fopen (SSDATA (encoded), "rb");
  if (!f)
    report_file_error ("Opening source file", filename);

  if (fseeko (f, 0, SEEK_END) != 0)
    {
      emacs_fclose (f);
      report_file_error ("Seeking source file", filename);
    }
  off_t sz = ftello (f);
  if (sz < 0)
    {
      emacs_fclose (f);
      report_file_error ("Querying source file size", filename);
    }
  rewind (f);

  /* Read the whole file in one shot (source .el files are small).  */
  char *buf = xmalloc (sz);
  size_t got = fread (buf, 1, sz, f);
  bool err = ferror (f);
  emacs_fclose (f);
  if (err)
    {
      xfree (buf);
      xsignal2 (Qfile_notify_error, build_string ("hashing failed"), filename);
    }

  Lisp_Object acc = make_unibyte_string (buf, got);
  xfree (buf);

  Lisp_Object md5_args[5] = { intern_c_string ("md5"), acc, Qnil, Qnil,
			      intern_c_string ("binary") };
  Lisp_Object digest = Ffuncall (5, md5_args);
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

  DEFVAR_LISP ("comp-zeln-to-el-h", Vzeln_to_el_h,
	       doc: /* Hash table zeln-filename -> el-filename.
Mirrors `comp-eln-to-el-h'; used so loading a .zeln reports the source
.elc in `load-file-name' / `load-history'.  */);
  Vzeln_to_el_h = CALLN (Fmake_hash_table, QCtest, Qequal);

  staticpro (&zeln_loadsearch_re_list);
  zeln_loadsearch_re_list = Qnil;

  defsubr (&Scomp_z_load_zeln);
  defsubr (&Scomp_z_write_spike_zunit);
  defsubr (&Scomp_z_write_zunit);
  defsubr (&Scomp_z_el_to_zeln_rel_filename);

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
