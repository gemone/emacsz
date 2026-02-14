/* C++20 forward declarations for GNU Emacs Lisp types -*- coding:
utf-8 -*-

Copyright (C) 2026 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>. */

#ifndef EMACS_LISP_FWD_HPP
#define EMACS_LISP_FWD_HPP

/* Forward declarations for core Emacs Lisp types.
   This header provides minimal type definitions needed for C++
   wrappers without requiring the full lisp.h (which has gnulib
   dependencies). */

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace emacs
{

/* EMACS_INT - signed integer for Emacs values */
#ifndef EMACS_INT
using EMACS_INT = long long;
#endif
using EMACS_UINT = unsigned long long;

/* Tagged pointer representation */
using Lisp_Word = EMACS_INT;

/* Check if we're using LSB tagging (most modern platforms) */
#ifndef USE_LSB_TAG
# define USE_LSB_TAG 1
#endif

/* Tag bits */
enum
{
  GCTYPEBITS = 3
};

/* Lisp type enumeration */
enum class LispType : uint8_t
{
  Symbol = 0,
  Unused0 = 1,
  Int0 = 2,
  String = 4,
  Vectorlike = 5,
  Cons = USE_LSB_TAG ? 3 : 6,
  Float = 7,
  Int1 = USE_LSB_TAG ? 6 : 3
};

/* Lisp_Object - tagged pointer or integer.
   This must match the layout expected by the Emacs GC. */
struct Lisp_Object
{
  Lisp_Word i;

  constexpr Lisp_Object () : i (0) {}
  constexpr explicit Lisp_Object (Lisp_Word v) : i (v) {}

  [[nodiscard]] constexpr Lisp_Word raw () const { return i; }
};

static_assert (sizeof (Lisp_Object) == sizeof (Lisp_Word),
	       "Lisp_Object must have same size as Lisp_Word");

/* Type checking macros (inline functions for C++) */
[[nodiscard]] inline constexpr LispType
XTYPE (Lisp_Object o)
{
  return static_cast<LispType> (o.raw () & ((1 << GCTYPEBITS) - 1));
}

[[nodiscard]] inline constexpr bool
NILP (Lisp_Object o)
{
  return o.raw () == 0;
}

[[nodiscard]] inline constexpr bool
SYMBOLP (Lisp_Object o)
{
  return XTYPE (o) == LispType::Symbol;
}

[[nodiscard]] inline constexpr bool
CONSP (Lisp_Object o)
{
  return XTYPE (o) == LispType::Cons;
}

[[nodiscard]] inline constexpr bool
STRINGP (Lisp_Object o)
{
  return XTYPE (o) == LispType::String;
}

[[nodiscard]] inline constexpr bool
FIXNUMP (Lisp_Object o)
{
  auto t = XTYPE (o);
  return t == LispType::Int0 || t == LispType::Int1;
}

[[nodiscard]] inline constexpr bool
FLOATP (Lisp_Object o)
{
  return XTYPE (o) == LispType::Float;
}

[[nodiscard]] inline constexpr bool
VECTORP (Lisp_Object o)
{
  return XTYPE (o) == LispType::Vectorlike;
}

[[nodiscard]] inline constexpr bool
EQ (Lisp_Object a, Lisp_Object b)
{
  return a.raw () == b.raw ();
}

/* Fixnum extraction */
[[nodiscard]] inline constexpr EMACS_INT
XFIXNUM (Lisp_Object o)
{
  return (o.raw () >> (GCTYPEBITS - 1));
}

/* Make fixnum */
[[nodiscard]] inline constexpr Lisp_Object
make_fixnum (EMACS_INT v)
{
  return Lisp_Object ((v << (GCTYPEBITS - 1))
		      + (USE_LSB_TAG ? 2 : 4));
}

/* Cons cell access - these require the actual struct Lisp_Cons */
struct Lisp_Cons;
struct Lisp_Symbol;
struct Lisp_String;
struct Lisp_Vector;
struct Lisp_Float;
struct Lisp_Subr;

/* Forward declarations for specpdl */
union specbinding;
using specpdl_ref = ptrdiff_t;

/* Placeholder for Qnil and other globals */
extern Lisp_Object Qnil;
extern Lisp_Object Qt;

/* Placeholder for extern "C" functions we'll link against */
extern "C"
{
  /* Cons operations */
  extern Lisp_Object Fcons (Lisp_Object, Lisp_Object);
  extern Lisp_Object XCAR (Lisp_Object);
  extern Lisp_Object XCDR (Lisp_Object);
  extern void XSETCAR (Lisp_Object, Lisp_Object);
  extern void XSETCDR (Lisp_Object, Lisp_Object);

  /* String operations */
  extern char *SSDATA (Lisp_Object);
  extern ptrdiff_t SBYTES (Lisp_Object);
  extern int SREF (Lisp_Object, ptrdiff_t);
  extern Lisp_Object make_string (const char *, ptrdiff_t);

  /* Vector operations */
  extern ptrdiff_t ASIZE (Lisp_Object);
  extern Lisp_Object AREF (Lisp_Object, ptrdiff_t);
  extern void ASET (Lisp_Object, ptrdiff_t, Lisp_Object);
  extern Lisp_Object make_vector (ptrdiff_t, Lisp_Object);

  /* Symbol operations */
  extern Lisp_Object intern_1 (const char *, ptrdiff_t);
  extern Lisp_Object SYMBOL_NAME (Lisp_Object);
  extern Lisp_Object symbol_value (Lisp_Object);
  extern void set_symbol_value (Lisp_Object, Lisp_Object);
  extern bool is_symbol_bound (Lisp_Object);

  /* Float operations */
  extern Lisp_Object make_float (double);
  extern double XFLOAT_DATA (Lisp_Object);

  /* Evaluator operations */
  extern Lisp_Object Feval (Lisp_Object, Lisp_Object);
  extern Lisp_Object Ffuncall (ptrdiff_t, Lisp_Object *);
  extern Lisp_Object Fapply (ptrdiff_t, Lisp_Object *);
  extern void specbind (Lisp_Object, Lisp_Object);
  extern Lisp_Object unbind_to (specpdl_ref, Lisp_Object);
  extern void record_unwind_protect (void (*) (Lisp_Object),
				     Lisp_Object);
  extern specpdl_ref specpdl_ptr_index (void);

  /* Equality */
  extern Lisp_Object Fequal (Lisp_Object, Lisp_Object);

  /* Documentation */
  extern Lisp_Object Fdocumentation (Lisp_Object, Lisp_Object);

  /* Debug */
  extern bool debug_on_next_call;
  extern ptrdiff_t backtrace_p_count (void);

  /* Memory */
  extern void *lisp_malloc (size_t);
  extern void lisp_free (void *);
}

/* FUNCTIONP macro placeholder */
[[nodiscard]] inline bool
FUNCTIONP (Lisp_Object o)
{
  /* Subrs, lambdas, closures are vectorlike or cons */
  return VECTORP (o) || CONSP (o);
}

/* Pseudovector type checking - placeholder */
#define PVEC_SUBR 0
#define PVEC_MODULE_FUNCTION 16

[[nodiscard]] inline bool
PSEUDOVECTORP (Lisp_Object, int)
{
  /* Placeholder - needs real implementation */
  return false;
}

/* XUNTAG placeholder */
template <typename T>
[[nodiscard]] inline T *
XUNTAG (Lisp_Object, LispType, T *)
{
  /* Placeholder - needs real implementation */
  return nullptr;
}

}

#endif /* EMACS_LISP_FWD_HPP */
