/* C++20 wrapper for GNU Emacs Lisp types -*- coding: utf-8 -*-

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

#ifndef EMACS_LISP_HPP
#define EMACS_LISP_HPP

#include "emacs_lisp_fwd.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string_view>
#include <type_traits>

namespace emacs
{

/* Forward declarations */
class Object;
class Symbol;
class Cons;
class String;
class Vector;
class Integer;
class Float;
class Function;

/* Type traits for checking Lisp types at compile time */
template <typename T> struct is_lisp_type : std::false_type
{
};

template <> struct is_lisp_type<Object> : std::true_type
{
};

template <> struct is_lisp_type<Symbol> : std::true_type
{
};

template <> struct is_lisp_type<Cons> : std::true_type
{
};

template <> struct is_lisp_type<String> : std::true_type
{
};

/* Core Lisp object wrapper - zero-cost abstraction over Lisp_Object

   This class provides type-safe operations on Lisp objects while
   maintaining exact binary compatibility with Lisp_Object. The
   sizeof(Object) == sizeof(Lisp_Object) is guaranteed. */
class Object
{
public:
  /* Default constructor creates nil */
  constexpr Object () noexcept : obj_ (LISP_INITIALLY (0)) {}

  /* Implicit conversion from raw Lisp_Object - zero cost */
  constexpr Object (Lisp_Object obj) noexcept : obj_ (obj) {}

  /* Implicit conversion to raw Lisp_Object - zero cost */
  constexpr operator Lisp_Object () const noexcept { return obj_; }

  /* Get raw Lisp_Object */
  [[nodiscard]] constexpr Lisp_Object raw () const noexcept
  {
    return obj_;
  }

  /* Type predicates - map directly to C macros */
  [[nodiscard]] bool is_nil () const noexcept { return NILP (obj_); }

  [[nodiscard]] bool is_symbol () const noexcept
  {
    return SYMBOLP (obj_);
  }

  [[nodiscard]] bool is_cons () const noexcept
  {
    return CONSP (obj_);
  }

  [[nodiscard]] bool is_string () const noexcept
  {
    return STRINGP (obj_);
  }

  [[nodiscard]] bool is_integer () const noexcept
  {
    return FIXNUMP (obj_);
  }

  [[nodiscard]] bool is_float () const noexcept
  {
    return FLOATP (obj_);
  }

  [[nodiscard]] bool is_vector () const noexcept
  {
    return VECTORP (obj_);
  }

  [[nodiscard]] bool is_function () const noexcept
  {
    return FUNCTIONP (obj_);
  }

  [[nodiscard]] bool is_list () const noexcept
  {
    return CONSP (obj_) || NILP (obj_);
  }

  /* Equality */
  [[nodiscard]] bool eq (Object other) const noexcept
  {
    return EQ (obj_, other.obj_);
  }

  [[nodiscard]] bool equal (Object other) const noexcept
  {
    extern Lisp_Object Fequal (Lisp_Object, Lisp_Object);
    return !NILP (Fequal (obj_, other.obj_));
  }

  /* Type code */
  [[nodiscard]] LispType type () const noexcept
  {
    return static_cast<LispType> (XTYPE (obj_));
  }

  /* Get type name as string (for debugging) */
  [[nodiscard]] const char *type_name () const noexcept
  {
    if (is_nil ())
      return "nil";
    if (is_symbol ())
      return "symbol";
    if (is_cons ())
      return "cons";
    if (is_string ())
      return "string";
    if (is_integer ())
      return "integer";
    if (is_float ())
      return "float";
    if (is_vector ())
      return "vector";
    return "unknown";
  }

protected:
  Lisp_Object obj_;
};

static_assert (sizeof (Object) == sizeof (Lisp_Object),
	       "Object must have same size as Lisp_Object");

/* Symbol wrapper */
class Symbol : public Object
{
public:
  using Object::Object;

  /* Create from symbol name */
  [[nodiscard]] static Symbol intern (std::string_view name) noexcept
  {
    extern Lisp_Object intern_1 (const char *, ptrdiff_t);
    return Symbol (
      intern_1 (name.data (), static_cast<ptrdiff_t> (name.size ())));
  }

  /* Get symbol name */
  [[nodiscard]] std::string_view name () const noexcept
  {
    eassert (SYMBOLP (obj_));
    Lisp_Object name_obj = SYMBOL_NAME (obj_);
    ptrdiff_t len;
    char *data = SSDATA (name_obj);
    /* Get length from string */
    len = SBYTES (name_obj);
    return std::string_view (data, static_cast<size_t> (len));
  }

  /* Get symbol value */
  [[nodiscard]] Object value () const noexcept
  {
    extern Lisp_Object symbol_value (Lisp_Object);
    return Object (symbol_value (obj_));
  }

  /* Set symbol value */
  void set_value (Object val) noexcept
  {
    extern void set_symbol_value (Lisp_Object, Lisp_Object);
    set_symbol_value (obj_, val);
  }

  /* Check if symbol is bound */
  [[nodiscard]] bool is_bound () const noexcept
  {
    extern bool is_symbol_bound (Lisp_Object);
    return is_symbol_bound (obj_);
  }
};

/* Cons cell wrapper */
class Cons : public Object
{
public:
  using Object::Object;

  /* Get car */
  [[nodiscard]] Object car () const noexcept
  {
    eassert (CONSP (obj_));
    return Object (XCAR (obj_));
  }

  /* Get cdr */
  [[nodiscard]] Object cdr () const noexcept
  {
    eassert (CONSP (obj_));
    return Object (XCDR (obj_));
  }

  /* Set car */
  void set_car (Object val) noexcept
  {
    eassert (CONSP (obj_));
    XSETCAR (obj_, val);
  }

  /* Set cdr */
  void set_cdr (Object val) noexcept
  {
    eassert (CONSP (obj_));
    XSETCDR (obj_, val);
  }

  /* Construct a cons cell */
  [[nodiscard]] static Cons cons (Object car, Object cdr) noexcept
  {
    return Cons (Fcons (car, cdr));
  }
};

/* String wrapper */
class String : public Object
{
public:
  using Object::Object;

  /* Create from string_view */
  [[nodiscard]] static String make (std::string_view str) noexcept
  {
    extern Lisp_Object make_string (const char *, ptrdiff_t);
    return String (make_string (str.data (), static_cast<ptrdiff_t> (
					       str.size ())));
  }

  /* Get as string_view */
  [[nodiscard]] std::string_view view () const noexcept
  {
    eassert (STRINGP (obj_));
    ptrdiff_t len = SBYTES (obj_);
    return std::string_view (SSDATA (obj_),
			     static_cast<size_t> (len));
  }

  /* Get length */
  [[nodiscard]] ptrdiff_t length () const noexcept
  {
    eassert (STRINGP (obj_));
    return SBYTES (obj_);
  }

  /* Get character at position (0-indexed) */
  [[nodiscard]] int char_at (ptrdiff_t idx) const noexcept
  {
    eassert (STRINGP (obj_));
    eassert (idx >= 0 && idx < SBYTES (obj_));
    return SREF (obj_, idx);
  }
};

/* Integer wrapper */
class Integer : public Object
{
public:
  using Object::Object;

  /* Create from EMACS_INT */
  [[nodiscard]] static Integer make (EMACS_INT val) noexcept
  {
    return Integer (make_fixnum (val));
  }

  /* Get value as EMACS_INT */
  [[nodiscard]] EMACS_INT value () const noexcept
  {
    eassert (FIXNUMP (obj_));
    return XFIXNUM (obj_);
  }

  /* Implicit conversion to EMACS_INT */
  [[nodiscard]] operator EMACS_INT () const noexcept
  {
    return value ();
  }
};

/* Float wrapper */
class Float : public Object
{
public:
  using Object::Object;

  /* Create from double */
  [[nodiscard]] static Float make (double val) noexcept
  {
    return Float (make_float (val));
  }

  /* Get value as double */
  [[nodiscard]] double value () const noexcept
  {
    eassert (FLOATP (obj_));
    return XFLOAT_DATA (obj_);
  }

  /* Implicit conversion to double */
  [[nodiscard]] operator double () const noexcept { return value (); }
};

/* Vector wrapper */
class Vector : public Object
{
public:
  using Object::Object;

  /* Create vector of given size */
  [[nodiscard]] static Vector make (ptrdiff_t size) noexcept
  {
    return Vector (make_vector (size, Qnil));
  }

  /* Get size */
  [[nodiscard]] ptrdiff_t size () const noexcept
  {
    eassert (VECTORP (obj_));
    return ASIZE (obj_);
  }

  /* Get element at index */
  [[nodiscard]] Object at (ptrdiff_t idx) const noexcept
  {
    eassert (VECTORP (obj_));
    eassert (idx >= 0 && idx < ASIZE (obj_));
    return Object (AREF (obj_, idx));
  }

  /* Set element at index */
  void set (ptrdiff_t idx, Object val) noexcept
  {
    eassert (VECTORP (obj_));
    eassert (idx >= 0 && idx < ASIZE (obj_));
    ASET (obj_, idx, val);
  }

  /* Array subscript operator */
  [[nodiscard]] Object operator[] (ptrdiff_t idx) const noexcept
  {
    return at (idx);
  }
};

/* Function wrapper - for subrs, lambdas, and closures */
class Function : public Object
{
public:
  using Object::Object;

  /* Check if object is callable */
  [[nodiscard]] static bool is_callable (Object obj) noexcept
  {
    return FUNCTIONP (obj);
  }

  /* Get function documentation */
  [[nodiscard]] Object documentation () const noexcept
  {
    extern Lisp_Object Fdocumentation (Lisp_Object, Lisp_Object);
    return Object (Fdocumentation (obj_, Qnil));
  }
};

/* List iteration helper - provides range-based for support */
class ListIterator
{
public:
  constexpr explicit ListIterator (Object list) noexcept
      : current_ (list)
  {
  }

  [[nodiscard]] Object operator* () const noexcept
  {
    return Cons (current_).car ();
  }

  ListIterator &operator++ () noexcept
  {
    current_ = Cons (current_).cdr ();
    return *this;
  }

  [[nodiscard]] bool
  operator== (const ListIterator &other) const noexcept
  {
    return current_.eq (other.current_);
  }

  [[nodiscard]] bool
  operator!= (const ListIterator &other) const noexcept
  {
    return !(*this == other);
  }

private:
  Object current_;
};

/* List range for range-based for loops */
class ListRange
{
public:
  constexpr explicit ListRange (Object list) noexcept : list_ (list)
  {
  }

  [[nodiscard]] ListIterator begin () const noexcept
  {
    return ListIterator (list_);
  }

  [[nodiscard]] ListIterator end () const noexcept
  {
    return ListIterator (Object (Qnil));
  }

private:
  Object list_;
};
/* Build a list from objects */
[[nodiscard]] Object
build_list (std::span<Object const> items) noexcept;

/* Convenience function to iterate a list */
template <typename F>
void
for_each_in_list (Object list, F func) noexcept
{
  for (auto elem : ListRange (list))
    {
      func (elem);
    }
}

} // namespace emacs

/* extern "C" bridge functions for C compatibility */
extern "C"
{
  /* These provide C-callable wrappers for the C++ functions.
     They must never throw exceptions. */

  /* Check if a Lisp_Object is nil */
  [[nodiscard]] int emacs_object_is_nil (Lisp_Object obj) noexcept;

  /* Check if a Lisp_Object is a cons */
  [[nodiscard]] int emacs_object_is_cons (Lisp_Object obj) noexcept;

  /* Get car of cons */
  [[nodiscard]] Lisp_Object
  emacs_cons_car (Lisp_Object cons) noexcept;

  /* Get cdr of cons */
  [[nodiscard]] Lisp_Object
  emacs_cons_cdr (Lisp_Object cons) noexcept;

  /* Get symbol value */
  [[nodiscard]] Lisp_Object
  emacs_symbol_value (Lisp_Object sym) noexcept;

  /* Make a cons cell */
  [[nodiscard]] Lisp_Object emacs_cons (Lisp_Object car,
					Lisp_Object cdr) noexcept;

  /* Make a string */
  [[nodiscard]] Lisp_Object
  emacs_make_string (const char *data, ptrdiff_t len) noexcept;

  /* Check if symbol is bound */
  [[nodiscard]] int emacs_symbol_is_bound (Lisp_Object sym) noexcept;
}

#endif /* EMACS_LISP_HPP */
