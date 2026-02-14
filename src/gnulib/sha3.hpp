// src/gnulib/sha3.hpp
// C++20 replacements for gnulib SHA-3 hash family
// Replaces: sha3 (sha3-224, sha3-256, sha3-384, sha3-512)
// Based on FIPS 202 and the Keccak reference implementation

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace emacs::gnulib
{

// SHA-3 digest sizes (in bytes)
constexpr size_t SHA3_224_DIGEST_SIZE = 28;
constexpr size_t SHA3_256_DIGEST_SIZE = 32;
constexpr size_t SHA3_384_DIGEST_SIZE = 48;
constexpr size_t SHA3_512_DIGEST_SIZE = 64;

// SHA-3 digest types
using sha3_224_digest = std::array<uint8_t, SHA3_224_DIGEST_SIZE>;
using sha3_256_digest = std::array<uint8_t, SHA3_256_DIGEST_SIZE>;
using sha3_384_digest = std::array<uint8_t, SHA3_384_DIGEST_SIZE>;
using sha3_512_digest = std::array<uint8_t, SHA3_512_DIGEST_SIZE>;

namespace detail
{

inline uint64_t
load64_le (const uint8_t *data) noexcept
{
  return static_cast<uint64_t> (data[0])
       | (static_cast<uint64_t> (data[1]) << 8)
       | (static_cast<uint64_t> (data[2]) << 16)
       | (static_cast<uint64_t> (data[3]) << 24)
       | (static_cast<uint64_t> (data[4]) << 32)
       | (static_cast<uint64_t> (data[5]) << 40)
       | (static_cast<uint64_t> (data[6]) << 48)
       | (static_cast<uint64_t> (data[7]) << 56);
}

inline void
store64_le (uint8_t *data, uint64_t value) noexcept
{
  data[0] = static_cast<uint8_t> (value);
  data[1] = static_cast<uint8_t> (value >> 8);
  data[2] = static_cast<uint8_t> (value >> 16);
  data[3] = static_cast<uint8_t> (value >> 24);
  data[4] = static_cast<uint8_t> (value >> 32);
  data[5] = static_cast<uint8_t> (value >> 40);
  data[6] = static_cast<uint8_t> (value >> 48);
  data[7] = static_cast<uint8_t> (value >> 56);
}

inline constexpr uint64_t
rotl64 (uint64_t x, int n) noexcept
{
  return (x << n) | (x >> (64 - n));
}

static constexpr uint64_t KECCAK_RC[24]
  = { 0x0000000000000001ULL, 0x0000000000008082ULL,
      0x800000000000808aULL, 0x8000000080008000ULL,
      0x0000000080008081ULL, 0x8000000000000080ULL,
      0x0000000080000001ULL, 0x8000000080008008ULL,
      0x0000000000000088ULL, 0x000000008000008bULL,
      0x000000008000008aULL, 0x8000000000008089ULL,
      0x8000000000008003ULL, 0x8000000000008002ULL,
      0x8000000000000080ULL, 0x000000000000800aULL,
      0x800000008000000aULL, 0x8000000080008081ULL,
      0x8000000000008080ULL, 0x0000000080000001ULL,
      0x8000000080008008ULL, 0x0000000000000000ULL,
      0x0000000000008003ULL, 0x000000008000000cULL
    };

static constexpr int KECCAK_ROTC[24]
  = { 1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
      27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44 };

static constexpr int KECCAK_PILN[24]
  = { 10, 7,  11, 17, 18, 3, 5, 16, 8,  21, 24, 4,
      15, 23, 19, 13, 12, 2, 20, 14, 22, 9,  6,  1 };

// Keccak-f[1600] permutation
inline void
keccak_f (std::array<uint64_t, 25> &st) noexcept
{
  for (int round = 0; round < 24; ++round)
    {
      // Theta
      std::array<uint64_t, 5> bc;
      for (int i = 0; i < 5; ++i)
        bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];

      for (int i = 0; i < 5; ++i)
        {
          uint64_t t = bc[(i + 4) % 5] ^ rotl64 (bc[(i + 1) % 5], 1);
          for (int j = 0; j < 25; j += 5)
            st[i + j] ^= t;
        }

      // Rho and Pi
      uint64_t t = st[1];
      for (int i = 0; i < 24; ++i)
        {
          int j = KECCAK_PILN[i];
          uint64_t bc0 = st[j];
          st[j] = rotl64 (t, KECCAK_ROTC[i]);
          t = bc0;
        }

      // Chi
      for (int j = 0; j < 25; j += 5)
        {
          std::array<uint64_t, 5> bc;
          for (int i = 0; i < 5; ++i)
            bc[i] = st[i + j];
          for (int i = 0; i < 5; ++i)
            st[i + j] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }

      // Iota
      st[0] ^= KECCAK_RC[round];
    }
}

}; // namespace detail

// SHA3-256 Context
class sha3_256_context
{
public:
  sha3_256_context () noexcept { reset (); }

  void reset () noexcept
  {
    state_.fill (0);
    buffer_len_ = 0;
  }

  void update (const void *data, size_t len) noexcept;
  void finalize (sha3_256_digest &digest) noexcept;

  [[nodiscard]] sha3_256_digest finalize () noexcept
  {
    sha3_256_digest result;
    finalize (result);
    return result;
  }

private:
  std::array<uint64_t, 25> state_;
  std::array<uint8_t, 136> buffer_;
  size_t buffer_len_;
};

// SHA3-224 Context
class sha3_224_context
{
public:
  sha3_224_context () noexcept { reset (); }

  void reset () noexcept
  {
    state_.fill (0);
    buffer_len_ = 0;
  }

  void update (const void *data, size_t len) noexcept;
  void finalize (sha3_224_digest &digest) noexcept;

  [[nodiscard]] sha3_224_digest finalize () noexcept
  {
    sha3_224_digest result;
    finalize (result);
    return result;
  }

private:
  std::array<uint64_t, 25> state_;
  std::array<uint8_t, 144> buffer_;
  size_t buffer_len_;
};

// SHA3-384 Context
class sha3_384_context
{
public:
  sha3_384_context () noexcept { reset (); }

  void reset () noexcept
  {
    state_.fill (0);
    buffer_len_ = 0;
  }

  void update (const void *data, size_t len) noexcept;
  void finalize (sha3_384_digest &digest) noexcept;

  [[nodiscard]] sha3_384_digest finalize () noexcept
  {
    sha3_384_digest result;
    finalize (result);
    return result;
  }

private:
  std::array<uint64_t, 25> state_;
  std::array<uint8_t, 104> buffer_;
  size_t buffer_len_;
};

// SHA3-512 Context
class sha3_512_context
{
public:
  sha3_512_context () noexcept { reset (); }

  void reset () noexcept
  {
    state_.fill (0);
    buffer_len_ = 0;
  }

  void update (const void *data, size_t len) noexcept;
  void finalize (sha3_512_digest &digest) noexcept;

  [[nodiscard]] sha3_512_digest finalize () noexcept
  {
    sha3_512_digest result;
    finalize (result);
    return result;
  }

private:
  std::array<uint64_t, 25> state_;
  std::array<uint8_t, 72> buffer_;
  size_t buffer_len_;
};

// SHA3-256 implementation
inline void
sha3_256_context::update (const void *data, size_t len) noexcept
{
  const auto *input = static_cast<const uint8_t *> (data);
  constexpr size_t RATE = 136;

  while (len > 0)
    {
      size_t to_copy = std::min (len, RATE - buffer_len_);
      std::memcpy (buffer_.data () + buffer_len_, input, to_copy);
      buffer_len_ += to_copy;
      input += to_copy;
      len -= to_copy;

      if (buffer_len_ == RATE)
        {
          for (size_t i = 0; i < RATE; i += 8)
            state_[i / 8] ^= detail::load64_le (buffer_.data () + i);
          detail::keccak_f (state_);
          buffer_len_ = 0;
        }
    }
}

inline void
sha3_256_context::finalize (sha3_256_digest &digest) noexcept
{
  constexpr size_t RATE = 136;
  std::array<uint8_t, RATE> buf{};
  std::memcpy (buf.data (), buffer_.data (), buffer_len_);
  buf[buffer_len_] = 0x06;
  buf[RATE - 1] |= 0x80;

  for (size_t i = 0; i < RATE; i += 8)
    state_[i / 8] ^= detail::load64_le (buf.data () + i);
  detail::keccak_f (state_);

  for (size_t i = 0; i < SHA3_256_DIGEST_SIZE; i += 8)
    detail::store64_le (digest.data () + i, state_[i / 8]);
}

// SHA3-224 implementation
inline void
sha3_224_context::update (const void *data, size_t len) noexcept
{
  const auto *input = static_cast<const uint8_t *> (data);
  constexpr size_t RATE = 144;

  while (len > 0)
    {
      size_t to_copy = std::min (len, RATE - buffer_len_);
      std::memcpy (buffer_.data () + buffer_len_, input, to_copy);
      buffer_len_ += to_copy;
      input += to_copy;
      len -= to_copy;

      if (buffer_len_ == RATE)
        {
          for (size_t i = 0; i < RATE; i += 8)
            state_[i / 8] ^= detail::load64_le (buffer_.data () + i);
          detail::keccak_f (state_);
          buffer_len_ = 0;
        }
    }
}

inline void
sha3_224_context::finalize (sha3_224_digest &digest) noexcept
{
  constexpr size_t RATE = 144;
  std::array<uint8_t, RATE> buf{};
  std::memcpy (buf.data (), buffer_.data (), buffer_len_);
  buf[buffer_len_] = 0x06;
  buf[RATE - 1] |= 0x80;

  for (size_t i = 0; i < RATE; i += 8)
    state_[i / 8] ^= detail::load64_le (buf.data () + i);
  detail::keccak_f (state_);

  for (size_t i = 0; i < SHA3_224_DIGEST_SIZE; i += 8)
    detail::store64_le (digest.data () + i, state_[i / 8]);
}

// SHA3-384 implementation
inline void
sha3_384_context::update (const void *data, size_t len) noexcept
{
  const auto *input = static_cast<const uint8_t *> (data);
  constexpr size_t RATE = 104;

  while (len > 0)
    {
      size_t to_copy = std::min (len, RATE - buffer_len_);
      std::memcpy (buffer_.data () + buffer_len_, input, to_copy);
      buffer_len_ += to_copy;
      input += to_copy;
      len -= to_copy;

      if (buffer_len_ == RATE)
        {
          for (size_t i = 0; i < RATE; i += 8)
            state_[i / 8] ^= detail::load64_le (buffer_.data () + i);
          detail::keccak_f (state_);
          buffer_len_ = 0;
        }
    }
}

inline void
sha3_384_context::finalize (sha3_384_digest &digest) noexcept
{
  constexpr size_t RATE = 104;
  std::array<uint8_t, RATE> buf{};
  std::memcpy (buf.data (), buffer_.data (), buffer_len_);
  buf[buffer_len_] = 0x06;
  buf[RATE - 1] |= 0x80;

  for (size_t i = 0; i < RATE; i += 8)
    state_[i / 8] ^= detail::load64_le (buf.data () + i);
  detail::keccak_f (state_);

  for (size_t i = 0; i < SHA3_384_DIGEST_SIZE; i += 8)
    detail::store64_le (digest.data () + i, state_[i / 8]);
}

// SHA3-512 implementation
inline void
sha3_512_context::update (const void *data, size_t len) noexcept
{
  const auto *input = static_cast<const uint8_t *> (data);
  constexpr size_t RATE = 72;

  while (len > 0)
    {
      size_t to_copy = std::min (len, RATE - buffer_len_);
      std::memcpy (buffer_.data () + buffer_len_, input, to_copy);
      buffer_len_ += to_copy;
      input += to_copy;
      len -= to_copy;

      if (buffer_len_ == RATE)
        {
          for (size_t i = 0; i < RATE; i += 8)
            state_[i / 8] ^= detail::load64_le (buffer_.data () + i);
          detail::keccak_f (state_);
          buffer_len_ = 0;
        }
    }
}

inline void
sha3_512_context::finalize (sha3_512_digest &digest) noexcept
{
  constexpr size_t RATE = 72;
  std::array<uint8_t, RATE> buf{};
  std::memcpy (buf.data (), buffer_.data (), buffer_len_);
  buf[buffer_len_] = 0x06;
  buf[RATE - 1] |= 0x80;

  for (size_t i = 0; i < RATE; i += 8)
    state_[i / 8] ^= detail::load64_le (buf.data () + i);
  detail::keccak_f (state_);

  for (size_t i = 0; i < SHA3_512_DIGEST_SIZE; i += 8)
    detail::store64_le (digest.data () + i, state_[i / 8]);
}

// One-shot functions
[[nodiscard]] inline sha3_256_digest
sha3_256 (const void *data, size_t len) noexcept
{
  sha3_256_context ctx;
  ctx.update (data, len);
  return ctx.finalize ();
}

[[nodiscard]] inline sha3_256_digest
sha3_256 (std::string_view data) noexcept
{
  return sha3_256 (data.data (), data.size ());
}

[[nodiscard]] inline sha3_224_digest
sha3_224 (const void *data, size_t len) noexcept
{
  sha3_224_context ctx;
  ctx.update (data, len);
  return ctx.finalize ();
}

[[nodiscard]] inline sha3_224_digest
sha3_224 (std::string_view data) noexcept
{
  return sha3_224 (data.data (), data.size ());
}

[[nodiscard]] inline sha3_384_digest
sha3_384 (const void *data, size_t len) noexcept
{
  sha3_384_context ctx;
  ctx.update (data, len);
  return ctx.finalize ();
}

[[nodiscard]] inline sha3_384_digest
sha3_384 (std::string_view data) noexcept
{
  return sha3_384 (data.data (), data.size ());
}

[[nodiscard]] inline sha3_512_digest
sha3_512 (const void *data, size_t len) noexcept
{
  sha3_512_context ctx;
  ctx.update (data, len);
  return ctx.finalize ();
}

[[nodiscard]] inline sha3_512_digest
sha3_512 (std::string_view data) noexcept
{
  return sha3_512 (data.data (), data.size ());
}

// Hex conversion helper
template <size_t N>
[[nodiscard]] inline std::string
sha3_digest_to_hex (const std::array<uint8_t, N> &digest)
{
  std::ostringstream oss;
  oss << std::hex << std::setfill ('0');
  for (uint8_t byte : digest)
    oss << std::setw (2) << static_cast<int> (byte);
  return oss.str ();
}

// Hex output functions
[[nodiscard]] inline std::string
sha3_256_hex (const void *data, size_t len)
{
  return sha3_digest_to_hex (sha3_256 (data, len));
}

[[nodiscard]] inline std::string
sha3_256_hex (std::string_view data)
{
  return sha3_digest_to_hex (sha3_256 (data));
}

[[nodiscard]] inline std::string
sha3_224_hex (const void *data, size_t len)
{
  return sha3_digest_to_hex (sha3_224 (data, len));
}

[[nodiscard]] inline std::string
sha3_224_hex (std::string_view data)
{
  return sha3_digest_to_hex (sha3_224 (data));
}

[[nodiscard]] inline std::string
sha3_384_hex (const void *data, size_t len)
{
  return sha3_digest_to_hex (sha3_384 (data, len));
}

[[nodiscard]] inline std::string
sha3_384_hex (std::string_view data)
{
  return sha3_digest_to_hex (sha3_384 (data));
}

[[nodiscard]] inline std::string
sha3_512_hex (const void *data, size_t len)
{
  return sha3_digest_to_hex (sha3_512 (data, len));
}

[[nodiscard]] inline std::string
sha3_512_hex (std::string_view data)
{
  return sha3_digest_to_hex (sha3_512 (data));
}

}
