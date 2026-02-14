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

#include <config.h>

#include "emacs_lisp.hpp"

namespace emacs
{

Object
build_list (std::span<Object const> items) noexcept
{
  if (items.empty ())
    return Object (Qnil);

  Lisp_Object result = Qnil;
  for (ptrdiff_t i = static_cast<ptrdiff_t> (items.size ()) - 1;
       i >= 0; --i)
    result = Fcons (items[static_cast<size_t> (i)].raw (), result);

  return Object (result);
}

}

extern "C"
{
  int emacs_object_is_nil (Lisp_Object obj) noexcept
  {
    return NILP (obj);
  }

  int emacs_object_is_cons (Lisp_Object obj) noexcept
  {
    return CONSP (obj);
  }

  Lisp_Object emacs_cons_car (Lisp_Object cons) noexcept
  {
    eassert (CONSP (cons));
    return XCAR (cons);
  }

  Lisp_Object emacs_cons_cdr (Lisp_Object cons) noexcept
  {
    eassert (CONSP (cons));
    return XCDR (cons);
  }

  Lisp_Object emacs_symbol_value (Lisp_Object sym) noexcept
  {
    extern Lisp_Object symbol_value (Lisp_Object);
    return symbol_value (sym);
  }

  Lisp_Object emacs_cons (Lisp_Object car, Lisp_Object cdr) noexcept
  {
    return Fcons (car, cdr);
  }

  Lisp_Object emacs_make_string (const char *data,
				 ptrdiff_t len) noexcept
  {
    extern Lisp_Object make_string (const char *, ptrdiff_t);
    return make_string (data, len);
  }

  int emacs_symbol_is_bound (Lisp_Object sym) noexcept
  {
    extern bool is_symbol_bound (Lisp_Object);
    return is_symbol_bound (sym);
  }
}
