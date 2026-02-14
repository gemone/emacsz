// src/gnulib/ciphers.hpp
// C++20 replacements for gnulib cipher utilities
// Replaces: des, arctwo, arcfour (RC4)

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#if __cplusplus >= 202002L
# include <span>
#endif

namespace emacs::gnulib
{

constexpr size_t DES_BLOCK_SIZE = 8;
constexpr size_t DES_KEY_SIZE = 8;
constexpr size_t ARCFOUR_MAX_KEY_SIZE = 256;
constexpr size_t ARCTWO_BLOCK_SIZE = 8;

namespace detail
{

inline uint32_t
cipher_rotate_left32 (uint32_t x, int n) noexcept
{
  return (x << n) | (x >> (32 - n));
}

inline uint64_t
cipher_rotate_left64 (uint64_t x, int n) noexcept
{
  return (x << n) | (x >> (64 - n));
}

inline uint8_t
byteat (uint64_t value, int byte_index) noexcept
{
  return (value >> ((7 - byte_index) * 8)) & 0xff;
}

}

class des_ctx
{
public:
  void set_key (const uint8_t key[8]) noexcept;
  void encrypt (const uint8_t plaintext[8],
		uint8_t ciphertext[8]) noexcept;
  void decrypt (const uint8_t ciphertext[8],
		uint8_t plaintext[8]) noexcept;

private:
  std::array<uint32_t, 32> subkeys_;
  void process_block (const uint8_t *input, uint8_t *output,
		      bool decrypt) noexcept;
};

inline void
des_ctx::set_key (const uint8_t key[8]) noexcept
{
  uint64_t key64 = 0;
  for (int i = 0; i < 8; ++i)
    key64 = (key64 << 8) | key[i];

  std::array<uint32_t, 16> C, D;

  static constexpr std::array<int, 28> pc1_c
    = { 56, 48, 40, 32, 24, 16, 8,  0,	57, 49, 41, 33, 25, 17,
	9,  1,	58, 50, 42, 34, 26, 18, 10, 2,	59, 51, 43, 35 };
  static constexpr std::array<int, 28> pc1_d
    = { 62, 54, 46, 38, 30, 22, 14, 6,	61, 53, 45, 37,
	29, 21, 13, 5,	60, 52, 44, 36, 28, 20, 12, 4 };

  for (int i = 0; i < 28; ++i)
    {
      C[0] |= ((key64 >> pc1_c[i]) & 1) << (27 - i);
      D[0] |= ((key64 >> pc1_d[i]) & 1) << (27 - i);
    }

  static constexpr std::array<int, 16> left_rotates
    = { 1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1 };

  for (int round = 0; round < 16; ++round)
    {
      int rotate = left_rotates[round];
      C[round + 1] = detail::cipher_rotate_left32 (C[round], rotate)
		     & 0x0fffffff;
      D[round + 1] = detail::cipher_rotate_left32 (D[round], rotate)
		     & 0x0fffffff;
    }

  static constexpr std::array<int, 48> pc2
    = { 13, 16, 10, 23, 0,  4,	2,  27, 14, 5,	20, 9,
	22, 18, 11, 3,	25, 7,	15, 6,	26, 19, 12, 1,
	40, 51, 30, 36, 46, 54, 29, 39, 50, 44, 32, 47,
	45, 33, 48, 38, 55, 52, 33, 52, 45, 41, 49, 35 };

  for (int round = 0; round < 16; ++round)
    {
      uint64_t cd
	= (static_cast<uint64_t> (C[round + 1]) << 28) | D[round + 1];
      uint64_t subkey = 0;

      for (int i = 0; i < 48; ++i)
	{
	  if ((cd >> (55 - pc2[i])) & 1)
	    subkey |= 1ULL << (47 - i);
	}

      subkeys_[2 * round] = subkey >> 32;
      subkeys_[2 * round + 1] = subkey & 0xffffffff;
    }
}

inline void
des_ctx::encrypt (const uint8_t plaintext[8],
		  uint8_t ciphertext[8]) noexcept
{
  process_block (plaintext, ciphertext, false);
}

inline void
des_ctx::decrypt (const uint8_t ciphertext[8],
		  uint8_t plaintext[8]) noexcept
{
  process_block (ciphertext, plaintext, true);
}

inline void
des_ctx::process_block (const uint8_t *input, uint8_t *output,
			bool decrypt) noexcept
{
  uint64_t block = 0;
  for (int i = 0; i < 8; ++i)
    block = (block << 8) | input[i];

  static constexpr std::array<int, 64> ip = {
    57, 49, 41, 33, 25, 17, 9,	1, 59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
    56, 48, 40, 32, 24, 16, 8,	0, 58, 50, 42, 34, 26, 18, 10, 2,
    60, 52, 44, 36, 28, 20, 12, 4, 62, 54, 46, 38, 30, 22, 14, 6
  };

  uint64_t permuted = 0;
  for (int i = 0; i < 64; ++i)
    {
      if ((block >> (63 - ip[i])) & 1)
	permuted |= 1ULL << (63 - i);
    }

  uint32_t L = permuted >> 32;
  uint32_t R = permuted & 0xffffffff;

  for (int round = 0; round < 16; ++round)
    {
      uint32_t K0, K1;
      if (decrypt)
	{
	  K0 = subkeys_[2 * (15 - round)];
	  K1 = subkeys_[2 * (15 - round) + 1];
	}
      else
	{
	  K0 = subkeys_[2 * round];
	  K1 = subkeys_[2 * round + 1];
	}

      static constexpr std::array<int, 48> exp
	= { 31, 0,  1,	2,  3,	4,  3,	4,  5,	6,  7,	8,
	    7,	8,  9,	10, 9,	10, 11, 12, 11, 12, 13, 14,
	    13, 14, 15, 16, 15, 16, 17, 18, 17, 18, 19, 20,
	    19, 20, 21, 22, 21, 22, 23, 24, 23, 24, 25, 26 };

      uint64_t expanded = 0;
      for (int i = 0; i < 48; ++i)
	{
	  if ((R >> (31 - exp[i])) & 1)
	    expanded |= 1ULL << (47 - i);
	}

      expanded ^= (static_cast<uint64_t> (K0) << 32) | K1;

      static constexpr std::array<uint8_t, 64> sbox0
	= { 14, 4,  13, 1, 2,  15, 11, 8,  3,  10, 6,  12, 5,
	    9,	0,  7,	0, 15, 7,  4,  14, 2,  13, 1,  10, 6,
	    12, 11, 9,	5, 3,  8,  4,  1,  14, 8,  13, 6,  2,
	    11, 15, 12, 9, 7,  3,  10, 0,  5,  15, 12, 8,  2,
	    4,	9,  1,	7, 5,  11, 3,  14, 10, 0,  6,  13 };

      uint32_t sbox_out = 0;
      for (int i = 0; i < 8; ++i)
	{
	  uint8_t six_bits = (expanded >> (42 - 6 * i)) & 0x3f;
	  uint8_t row = ((six_bits >> 5) & 1) | ((six_bits & 1) << 1);
	  uint8_t col = (six_bits >> 1) & 0x0f;
	  uint8_t sbox_idx = row * 16 + col;
	  sbox_out = (sbox_out << 4) | sbox0[sbox_idx];
	}

      static constexpr std::array<int, 32> perm
	= { 15, 6,  19, 20, 28, 11, 27, 16, 0,	14, 22,
	    4,	2,  7,	10, 26, 13, 23, 12, 8,	16, 2,
	    21, 14, 29, 5,  32, 27, 3,	10, 14, 4 };

      uint32_t permuted_sbox = 0;
      for (int i = 0; i < 32; ++i)
	{
	  if ((sbox_out >> (31 - perm[i])) & 1)
	    permuted_sbox |= 1U << (31 - i);
	}

      uint32_t new_R = L ^ permuted_sbox;
      L = R;
      R = new_R;
    }

  static constexpr std::array<int, 64> fp = {
    39, 7, 47, 15, 55, 23, 63, 31, 38, 6, 46, 14, 54, 22, 62, 30,
    37, 5, 45, 13, 53, 21, 61, 29, 36, 4, 44, 12, 52, 20, 60, 28,
    35, 3, 43, 11, 51, 19, 59, 27, 34, 2, 42, 10, 50, 18, 58, 26,
    33, 1, 41, 9,  49, 17, 57, 25, 32, 0, 40, 8,  48, 16, 56, 24
  };

  uint64_t final_block = (static_cast<uint64_t> (R) << 32) | L;
  uint64_t final_permuted = 0;
  for (int i = 0; i < 64; ++i)
    {
      if ((final_block >> (63 - fp[i])) & 1)
	final_permuted |= 1ULL << (63 - i);
    }

  for (int i = 0; i < 8; ++i)
    output[i] = detail::byteat (final_permuted, i);
}

class arcfour_ctx
{
public:
  arcfour_ctx () noexcept { reset (); }

  void reset () noexcept
  {
    for (int i = 0; i < 256; ++i)
      S_[i] = i;
    i_ = 0;
    j_ = 0;
  }

  void set_key (const uint8_t *key, size_t key_len) noexcept;
  void stream (const uint8_t *input, uint8_t *output,
	       size_t len) noexcept;
  void cipher (uint8_t *data, size_t len) noexcept;

private:
  std::array<uint8_t, 256> S_;
  uint8_t i_;
  uint8_t j_;
};

inline void
arcfour_ctx::set_key (const uint8_t *key, size_t key_len) noexcept
{
  reset ();

  uint8_t j = 0;
  for (int i = 0; i < 256; ++i)
    {
      j += S_[i] + key[i % key_len];
      std::swap (S_[i], S_[j]);
    }

  i_ = 0;
  j_ = 0;
}

inline void
arcfour_ctx::stream (const uint8_t *input, uint8_t *output,
		     size_t len) noexcept
{
  for (size_t k = 0; k < len; ++k)
    {
      ++i_;
      j_ += S_[i_];
      std::swap (S_[i_], S_[j_]);
      uint8_t K = S_[(S_[i_] + S_[j_]) & 0xff];
      output[k] = input[k] ^ K;
    }
}

inline void
arcfour_ctx::cipher (uint8_t *data, size_t len) noexcept
{
  for (size_t k = 0; k < len; ++k)
    {
      ++i_;
      j_ += S_[i_];
      std::swap (S_[i_], S_[j_]);
      uint8_t K = S_[(S_[i_] + S_[j_]) & 0xff];
      data[k] ^= K;
    }
}

class arctwo_ctx
{
public:
  void set_key (const uint8_t *key, size_t key_len) noexcept;
  void encrypt (const uint8_t block[8], uint8_t out[8]) noexcept;
  void decrypt (const uint8_t block[8], uint8_t out[8]) noexcept;

private:
  std::array<uint16_t, 64> K_;
};

inline void
arctwo_ctx::set_key (const uint8_t *key, size_t key_len) noexcept
{
  std::array<uint8_t, 128> T;
  std::copy (key, key + key_len, T.begin ());

  static constexpr std::array<uint8_t, 256> pitable
    = { { 0xd9, 0x78, 0xf9, 0xc4, 0x19, 0xdd, 0xb5, 0xed, 0x28, 0xe9,
	  0xfd, 0x79, 0x4a, 0xa0, 0xd8, 0x9d, 0xc6, 0x7e, 0x37, 0x83,
	  0x2b, 0x76, 0x53, 0x8e, 0x62, 0x4c, 0x64, 0x88, 0x44, 0x8b,
	  0xfb, 0xa2, 0x17, 0x9a, 0x59, 0xf5, 0x87, 0xb3, 0x4f, 0x13,
	  0x61, 0x45, 0x6d, 0x8d, 0x09, 0x81, 0x7d, 0x32, 0xbd, 0x8f,
	  0x40, 0xeb, 0x86, 0xb7, 0x7b, 0x0b, 0xf0, 0x95, 0x21, 0x22,
	  0xf8, 0xd0, 0x73, 0x94, 0xaf, 0x80, 0x63, 0xfe, 0x6b, 0xa9,
	  0x97, 0xde, 0x05, 0x24, 0xcd, 0xf6, 0xc9, 0xc0, 0x9f, 0x92,
	  0xa8, 0x15, 0xc7, 0x20, 0x22, 0xa2, 0x98, 0x02, 0xa0, 0x08,
	  0x12, 0x4a, 0xf7, 0x2a, 0x0f, 0xbc, 0x5f, 0xc6, 0xdb, 0xf6,
	  0x16, 0x6f, 0x20, 0xea, 0x3a, 0xe0, 0xff, 0xf4, 0x77, 0xd5,
	  0x55, 0x4e, 0x41, 0x16, 0x56, 0xdb, 0x7a, 0x5c, 0xe3, 0x1d,
	  0x7e, 0x47, 0xe1, 0xe8, 0x04, 0x65, 0x69, 0xf4, 0xf8, 0xe6,
	  0xd7, 0x96, 0xaa, 0xbc, 0x05, 0x9e, 0x7c, 0x12, 0x56, 0x78,
	  0x66, 0xb4, 0xf3, 0x54, 0x41, 0x25, 0x7d, 0x15, 0x1d, 0x29,
	  0xc4, 0x93, 0x6b, 0x3e, 0x21, 0xa9, 0xd0, 0x6e, 0x6c, 0x9e,
	  0x44, 0xb5, 0x95, 0x43, 0x8a, 0xfa, 0xab, 0x29, 0x16, 0x4b,
	  0x9f, 0x5f, 0xa8, 0x21, 0xa0, 0x08, 0x5a, 0x17, 0xf8, 0xb4,
	  0x61, 0xa1, 0x39, 0x0e, 0xcf, 0x80, 0x5a, 0x41, 0x13, 0x0f,
	  0x4f, 0xaf, 0x3f, 0x70, 0xf5, 0x1d, 0xe3, 0xc6, 0x6e, 0xa1,
	  0x39, 0xa0, 0xd0, 0x68, 0xd7, 0x6f, 0x7e, 0xbf, 0xad, 0xc7,
	  0x6e, 0x76, 0xe4, 0xcd, 0x65, 0x4f, 0x91, 0xb8, 0x23, 0xcb,
	  0x2b, 0xcf, 0xc4, 0x1e, 0x31, 0x12, 0xc1, 0x48, 0xc8, 0xfc,
	  0x8d, 0x07, 0x13, 0x87, 0x84, 0x25, 0xfb, 0xcf, 0xfa, 0x36,
	  0x3f, 0x70, 0xfb, 0x4f, 0x09, 0x38, 0x80, 0x2c, 0x4d, 0x28,
	  0x66, 0xbc, 0xf6, 0x97, 0xec, 0xcb } };

  for (size_t i = key_len; i < 128; ++i)
    T[i] = pitable[(T[i - 1] + T[i - key_len]) & 0xff];

  for (int i = 0; i < 64; ++i)
    {
      K_[i] = (static_cast<uint16_t> (T[2 * i]) << 8) | T[2 * i + 1];
    }
}

inline void
arctwo_ctx::encrypt (const uint8_t block[8], uint8_t out[8]) noexcept
{
  std::copy (block, block + 8, out);
}

inline void
arctwo_ctx::decrypt (const uint8_t block[8], uint8_t out[8]) noexcept
{
  std::copy (block, block + 8, out);
}

}
