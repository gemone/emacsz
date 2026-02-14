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

#ifndef EMACS_EVAL_HPP
#define EMACS_EVAL_HPP

#include <config.h>

#include "emacs_lisp.hpp"

namespace emacs
{

/* RAII wrapper for specpdl scope management

   This ensures proper unwind of specpdl entries when scope exits.
   MUST NOT throw exceptions - the destructor is noexcept. */
class SpecpdlGuard
{
public:
  SpecpdlGuard () noexcept;
  ~SpecpdlGuard () noexcept;

  SpecpdlGuard (SpecpdlGuard const &) = delete;
  SpecpdlGuard &operator= (SpecpdlGuard const &) = delete;
  SpecpdlGuard (SpecpdlGuard &&) noexcept;
  SpecpdlGuard &operator= (SpecpdlGuard &&) noexcept;

  [[nodiscard]] specpdl_ref count () const noexcept { return count_; }

private:
  specpdl_ref count_;
  bool valid_;
};

/* Evaluator wrapper providing C++20 interface to eval.c */
class Evaluator
{
public:
  /* Evaluate a Lisp form */
  [[nodiscard]] static Object
  eval (Object form, Object lexical = Object (Qnil)) noexcept
  {
    extern Lisp_Object Feval (Lisp_Object, Lisp_Object);
    return Object (Feval (form.raw (), lexical.raw ()));
  }

  /* Call a function with arguments */
  [[nodiscard]] static Object
  funcall (Object fn, std::span<Object const> args) noexcept
  {
    extern Lisp_Object Ffuncall (ptrdiff_t, Lisp_Object *);
    ptrdiff_t const nargs = static_cast<ptrdiff_t> (args.size ()) + 1;

    Lisp_Object *const args_array = static_cast<Lisp_Object *> (
      alloca (nargs * sizeof (Lisp_Object)));

    args_array[0] = fn.raw ();
    for (size_t i = 0; i < args.size (); ++i)
      args_array[i + 1] = args[i].raw ();

    return Object (Ffuncall (nargs, args_array));
  }

  /* Call a function with 0 arguments */
  [[nodiscard]] static Object call0 (Object fn) noexcept
  {
    return funcall (fn, {});
  }

  /* Call a function with 1 argument */
  [[nodiscard]] static Object call1 (Object fn, Object arg1) noexcept
  {
    Object const args[] = { arg1 };
    return funcall (fn, args);
  }

  /* Call a function with 2 arguments */
  [[nodiscard]] static Object call2 (Object fn, Object arg1,
				     Object arg2) noexcept
  {
    Object const args[] = { arg1, arg2 };
    return funcall (fn, args);
  }

  /* Call a function with 3 arguments */
  [[nodiscard]] static Object
  call3 (Object fn, Object arg1, Object arg2, Object arg3) noexcept
  {
    Object const args[] = { arg1, arg2, arg3 };
    return funcall (fn, args);
  }

  /* Apply a function to a list of arguments */
  [[nodiscard]] static Object apply (Object fn, Object args) noexcept
  {
    extern Lisp_Object Fapply (ptrdiff_t, Lisp_Object *);
    Lisp_Object const apply_args[] = { fn.raw (), args.raw () };
    return Object (
      Fapply (2, const_cast<Lisp_Object *> (apply_args)));
  }

  /* Bind a variable dynamically */
  static void bind (Object symbol, Object value) noexcept
  {
    specbind (symbol.raw (), value.raw ());
  }

  /* Get current specpdl count */
  [[nodiscard]] static specpdl_ref specpdl_count () noexcept;

  /* Unwind to a specpdl count */
  [[nodiscard]] static Object unbind_to (specpdl_ref count,
					 Object value) noexcept
  {
    extern Lisp_Object unbind_to (specpdl_ref, Lisp_Object);
    return Object (::unbind_to (count, value.raw ()));
  }

  /* Record an unwind protect function */
  static void record_unwind (void (*func) (Lisp_Object),
			     Object arg) noexcept
  {
    record_unwind_protect (func, arg.raw ());
  }

  /* Signal an error */
  [[noreturn]] static void signal (Object error_symbol, Object data)
  {
    extern AVOID Fsignal (Lisp_Object, Lisp_Object);
    Fsignal (error_symbol.raw (), data.raw ());
  }

  /* Throw to a catch tag */
  [[noreturn]] static void throw_to (Object tag, Object value)
  {
    extern AVOID Fthrow (Lisp_Object, Lisp_Object);
    Fthrow (tag.raw (), value.raw ());
  }

  /* Run a catch block */
  template <typename F>
  [[nodiscard]] static Object catch_ (Object tag, F &&func) noexcept
  {
    extern Lisp_Object internal_catch (Lisp_Object,
				       Lisp_Object (*) (Lisp_Object),
				       Lisp_Object);
    struct Wrapper
    {
      F *f;
      static Lisp_Object call (Lisp_Object arg)
      {
	return (*static_cast<F *> (arg)) (arg);
      }
    };
    Wrapper wrapper{ &func };
    Lisp_Object wrapper_arg;
    memcpy (&wrapper_arg, &wrapper, sizeof (wrapper));
    return Object (
      internal_catch (tag.raw (), Wrapper::call, wrapper_arg));
  }

  /* Check if in debugger */
  [[nodiscard]] static bool in_debugger () noexcept;

  /* Get current backtrace depth */
  [[nodiscard]] static ptrdiff_t backtrace_depth () noexcept;
};

/* Error condition wrapper */
class LispError
{
public:
  explicit LispError (Object symbol, Object data) noexcept
      : symbol_ (symbol), data_ (data)
  {
  }

  [[nodiscard]] Object symbol () const noexcept { return symbol_; }

  [[nodiscard]] Object data () const noexcept { return data_; }

private:
  Object symbol_;
  Object data_;
};

}

extern "C"
{
  /* C-callable evaluator functions */
  [[nodiscard]] Lisp_Object emacs_eval (Lisp_Object form) noexcept;
  [[nodiscard]] Lisp_Object
  emacs_funcall (Lisp_Object fn, ptrdiff_t nargs,
		 Lisp_Object *args) noexcept;
  void emacs_specbind (Lisp_Object symbol,
		       Lisp_Object value) noexcept;
  [[nodiscard]] Lisp_Object
  emacs_unbind_to (ptrdiff_t count, Lisp_Object value) noexcept;
}

#endif /* EMACS_EVAL_HPP */
