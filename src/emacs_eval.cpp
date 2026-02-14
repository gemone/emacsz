/* C++20 wrapper for GNU Emacs Lisp evaluator -*- coding: utf-8 -*-

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

#include "emacs_eval.hpp"

namespace emacs
{

SpecpdlGuard::SpecpdlGuard () noexcept
    : count_ (specpdl_count ()), valid_ (true)
{
}

SpecpdlGuard::~SpecpdlGuard () noexcept
{
  if (valid_)
    unbind_to (count_, Qnil);
}

SpecpdlGuard::SpecpdlGuard (SpecpdlGuard &&other) noexcept
    : count_ (other.count_), valid_ (other.valid_)
{
  other.valid_ = false;
}

SpecpdlGuard &
SpecpdlGuard::operator= (SpecpdlGuard &&other) noexcept
{
  if (this != &other)
    {
      if (valid_)
	unbind_to (count_, Qnil);
      count_ = other.count_;
      valid_ = other.valid_;
      other.valid_ = false;
    }
  return *this;
}

specpdl_ref
Evaluator::specpdl_count () noexcept
{
  extern specpdl_ref specpdl_ptr_index (void);
  return specpdl_ptr_index ();
}

bool
Evaluator::in_debugger () noexcept
{
  extern bool debug_on_next_call;
  return debug_on_next_call;
}

ptrdiff_t
Evaluator::backtrace_depth () noexcept
{
  extern ptrdiff_t backtrace_p_count (void);
  return backtrace_p_count ();
}

}

extern "C"
{
  Lisp_Object emacs_eval (Lisp_Object form) noexcept
  {
    extern Lisp_Object Feval (Lisp_Object, Lisp_Object);
    return Feval (form, Qnil);
  }

  Lisp_Object emacs_funcall (Lisp_Object fn, ptrdiff_t nargs,
			     Lisp_Object *args) noexcept
  {
    extern Lisp_Object Ffuncall (ptrdiff_t, Lisp_Object *);
    Lisp_Object *all_args = static_cast<Lisp_Object *> (
      alloca ((nargs + 1) * sizeof (Lisp_Object)));
    all_args[0] = fn;
    for (ptrdiff_t i = 0; i < nargs; ++i)
      all_args[i + 1] = args[i];
    return Ffuncall (nargs + 1, all_args);
  }

  void emacs_specbind (Lisp_Object symbol, Lisp_Object value) noexcept
  {
    specbind (symbol, value);
  }

  Lisp_Object emacs_unbind_to (ptrdiff_t count,
			       Lisp_Object value) noexcept
  {
    extern Lisp_Object unbind_to (specpdl_ref, Lisp_Object);
    return unbind_to (specpdl_count_to_ref (count), value);
  }
}
