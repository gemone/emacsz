/* Native-comp Zig path definitions (the `.zeln` subsystem).

This header is the C-facing contract for the HAVE_NATIVE_COMP_ZIG path
(tools/zeln-compile + src/compz.c).  It is intentionally minimal at the
M0/scaffold stage: it only declares syms_of_compz so that src/emacs.c can
register the subsystem's Lisp symbols.  comp.c / comp.h (the gccjit path)
are completely untouched by this subsystem; the two paths are physically
isolated (plan section 2).  */

#ifndef COMPZ_H
#define COMPZ_H

/* syms_of_compz is declared ONLY when the Zig native-comp path is
   enabled, so that an accidentally-unguarded caller fails to compile
   when the switch is off (rather than silently referencing an undefined
   symbol at link time).  Unlike comp.h, there is deliberately NO #else
   arm defining a no-op stub.  */
#ifdef HAVE_NATIVE_COMP_ZIG
extern void syms_of_compz (void);
#endif

#endif /* COMPZ_H */
