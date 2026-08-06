/* Minimal GMP-compatible header for the native Zig bignum package
   (tools/bignum).  It exposes exactly the types, macros and function
   prototypes Emacs's C sources need, with the same ABI as libgmp:
   64-bit sign-magnitude limbs and the classic mpz_t struct layout.
   The implementations live in tools/bignum/src/bignum.zig and are
   linked into temacs in place of -lgmp.  This shim intentionally does
   not reproduce the whole GMP header surface; it shadows the system
   <gmp.h> via the build's -I path so no GMP headers are required to
   compile Emacs on any target.  */

#ifndef __GNU_MP__
#define __GNU_MP__ 6

#include <stddef.h>		/* size_t */

/* 64-bit limb, size and bit-count types on LP64 (long) and LLP64
   (long long) hosts, matching the Zig exports' u64/i64 widths.  */
#if __SIZEOF_LONG__ == 8
typedef unsigned long int	mp_limb_t;
typedef signed long int		mp_limb_signed_t;
typedef signed long int		mp_size_t;
typedef unsigned long int	mp_bitcnt_t;
#else
typedef unsigned long long int	mp_limb_t;
typedef signed long long int	mp_limb_signed_t;
typedef signed long long int	mp_size_t;
typedef unsigned long long int	mp_bitcnt_t;
#endif

typedef struct
{
  int _mp_alloc;		/* Number of *limbs* allocated and pointed
				   to by the _mp_d field.  */
  int _mp_size;			/* abs(_mp_size) is the number of limbs the
				   last field points to.  If _mp_size is
				   negative this is a negative number.  */
  mp_limb_t *_mp_d;		/* Pointer to the limbs.  */
} __mpz_struct;

typedef __mpz_struct mpz_t[1];
typedef __mpz_struct *mpz_ptr;
typedef const __mpz_struct *mpz_srcptr;
typedef mp_limb_t *mp_ptr;
typedef const mp_limb_t *mp_srcptr;

#define GMP_NUMB_BITS  (8 * sizeof (mp_limb_t))

extern const int mp_bits_per_limb;

/* Function pointer types for the memory allocation callbacks, matching
   libgmp's declarations.  */
typedef void *(*gmp_alloc_func) (size_t);
typedef void *(*gmp_realloc_func) (void *, size_t, size_t);
typedef void (*gmp_free_func) (void *, size_t);

/* Memory callbacks (Emacs installs xmalloc-based functions).  */
void mp_set_memory_functions (gmp_alloc_func, gmp_realloc_func, gmp_free_func);
void mp_get_memory_functions (gmp_alloc_func *, gmp_realloc_func *, gmp_free_func *);

/* Lifecycle, conversions and comparisons.  */
void mpz_init (mpz_t);
void mpz_init2 (mpz_t, mp_bitcnt_t);
void mpz_clear (mpz_t);
void mpz_set_ui (mpz_t, unsigned long int);
void mpz_set_si (mpz_t, signed long int);
mp_limb_t mpz_get_ui (mpz_srcptr);
mp_limb_signed_t mpz_get_si (mpz_srcptr);
void mpz_set (mpz_t, mpz_srcptr);
void mpz_swap (mpz_t, mpz_t);
void mpz_neg (mpz_t, mpz_srcptr);
void mpz_abs (mpz_t, mpz_srcptr);
int mpz_sgn (mpz_srcptr);
mp_size_t mpz_size (mpz_srcptr);
size_t mpz_sizeinbase (mpz_srcptr, int);
int mpz_cmp (mpz_srcptr, mpz_srcptr);
int mpz_cmpabs (mpz_srcptr, mpz_srcptr);
int mpz_cmp_ui (mpz_srcptr, unsigned long int);
int mpz_cmp_si (mpz_srcptr, signed long int);
int mpz_cmp_d (mpz_srcptr, double);

/* Arithmetic.  */
void mpz_add (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_sub (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_add_ui (mpz_t, mpz_srcptr, unsigned long int);
void mpz_sub_ui (mpz_t, mpz_srcptr, unsigned long int);
void mpz_mul (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_mul_ui (mpz_t, mpz_srcptr, unsigned long int);
void mpz_mul_2exp (mpz_t, mpz_srcptr, mp_bitcnt_t);
void mpz_fdiv_q_2exp (mpz_t, mpz_srcptr, mp_bitcnt_t);
void mpz_addmul (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_addmul_ui (mpz_t, mpz_srcptr, unsigned long int);
void mpz_submul (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_pow_ui (mpz_t, mpz_srcptr, unsigned long int);
void mpz_ui_pow_ui (mpz_t, unsigned long int, unsigned long int);
void mpz_gcd (mpz_t, mpz_srcptr, mpz_srcptr);

/* Division.  */
void mpz_tdiv_qr (mpz_t, mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_tdiv_q (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_tdiv_r (mpz_t, mpz_srcptr, mpz_srcptr);
mp_limb_t mpz_tdiv_ui (mpz_srcptr, unsigned long int);
void mpz_fdiv_q (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_fdiv_r (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_fdiv_qr (mpz_t, mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_cdiv_q (mpz_t, mpz_srcptr, mpz_srcptr);
mp_limb_t mpz_fdiv_q_ui (mpz_t, mpz_srcptr, unsigned long int);
void mpz_divexact (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_init_set_ui (mpz_t, unsigned long int);

/* Bitwise operations and bit queries.  */
void mpz_and (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_ior (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_xor (mpz_t, mpz_srcptr, mpz_srcptr);
void mpz_com (mpz_t, mpz_srcptr);
int mpz_odd_p (mpz_srcptr);
mp_bitcnt_t mpz_popcount (mpz_srcptr);
mp_bitcnt_t mpz_scan1 (mpz_srcptr, mp_bitcnt_t);

/* Limbs API (zero-copy access to the magnitude).  */
mp_limb_t mpz_getlimbn (mpz_srcptr, mp_size_t);
mp_srcptr mpz_limbs_read (mpz_srcptr);
mp_ptr mpz_limbs_write (mpz_ptr, mp_size_t);
void mpz_limbs_finish (mpz_ptr, mp_size_t);
mpz_srcptr mpz_roinit_n (mpz_ptr, mp_srcptr, mp_size_t);

/* Byte import/export.  */
void mpz_import (mpz_ptr, size_t, int, size_t, int, size_t, const void *);
void *mpz_export (void *, size_t *, int, size_t, int, size_t, mpz_srcptr);

/* String and double conversion.  */
char *mpz_get_str (char *, int, mpz_srcptr);
int mpz_set_str (mpz_t, const char *, int);
double mpz_get_d (mpz_srcptr);
void mpz_set_d (mpz_t, double);

/* Fit predicates.  */
int mpz_fits_sint_p (mpz_srcptr);
int mpz_fits_slong_p (mpz_srcptr);
int mpz_fits_ulong_p (mpz_srcptr);

#endif /* __GNU_MP__ */
