// src/gnulib/crypto.hpp
// C++20 replacements for gnulib cryptographic functions
// Replaces: crypto/md5, crypto/sha1-buffer, crypto/sha256-buffer,
// crypto/sha512-buffer

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

constexpr size_t MD5_DIGEST_SIZE = 16;
constexpr size_t SHA1_DIGEST_SIZE = 20;
constexpr size_t SHA256_DIGEST_SIZE = 32;
constexpr size_t SHA512_DIGEST_SIZE = 64;

using md5_digest = std::array<uint8_t, MD5_DIGEST_SIZE>;
using sha1_digest = std::array<uint8_t, SHA1_DIGEST_SIZE>;
using sha256_digest = std::array<uint8_t, SHA256_DIGEST_SIZE>;
using sha512_digest = std::array<uint8_t, SHA512_DIGEST_SIZE>;

namespace detail
{
inline uint32_t
rotate_left (uint32_t x, int n) noexcept
{
  return (x << n) | (x >> (32 - n));
}

inline uint64_t
rotate_left64 (uint64_t x, int n) noexcept
{
  return (x << n) | (x >> (64 - n));
}

inline uint32_t
rotate_right (uint32_t x, int n) noexcept
{
  return (x >> n) | (x << (32 - n));
}

inline uint64_t
rotate_right64 (uint64_t x, int n) noexcept
{
  return (x >> n) | (x << (64 - n));
}
}

class md5_context
{
public:
  md5_context () noexcept { reset (); }

  void reset () noexcept
  {
    state_[0] = 0x67452301;
    state_[1] = 0xefcdab89;
    state_[2] = 0x98badcfe;
    state_[3] = 0x10325476;
    count_ = 0;
    buffer_len_ = 0;
  }

  void update (const void *data, size_t len) noexcept;
  void finalize (md5_digest &digest) noexcept;

  [[nodiscard]] md5_digest finalize () noexcept
  {
    md5_digest result;
    finalize (result);
    return result;
  }

private:
  void transform (const uint8_t block[64]) noexcept;

  std::array<uint32_t, 4> state_;
  uint64_t count_;
  std::array<uint8_t, 64> buffer_;
  size_t buffer_len_;
};

class sha1_context
{
public:
  sha1_context () noexcept { reset (); }

  void reset () noexcept
  {
    state_[0] = 0x67452301;
    state_[1] = 0xefcdab89;
    state_[2] = 0x98badcfe;
    state_[3] = 0x10325476;
    state_[4] = 0xc3d2e1f0;
    count_ = 0;
    buffer_len_ = 0;
  }

  void update (const void *data, size_t len) noexcept;
  void finalize (sha1_digest &digest) noexcept;

  [[nodiscard]] sha1_digest finalize () noexcept
  {
    sha1_digest result;
    finalize (result);
    return result;
  }

private:
  void transform (const uint8_t block[64]) noexcept;

  std::array<uint32_t, 5> state_;
  uint64_t count_;
  std::array<uint8_t, 64> buffer_;
  size_t buffer_len_;
};

inline void
md5_context::update (const void *data, size_t len) noexcept
{
  const auto *input = static_cast<const uint8_t *> (data);

  while (len > 0)
    {
      size_t to_copy = std::min (len, 64 - buffer_len_);
      std::memcpy (buffer_.data () + buffer_len_, input, to_copy);
      buffer_len_ += to_copy;
      input += to_copy;
      len -= to_copy;
      count_ += to_copy;

      if (buffer_len_ == 64)
	{
	  transform (buffer_.data ());
	  buffer_len_ = 0;
	}
    }
}

inline void
md5_context::transform (const uint8_t block[64]) noexcept
{
  static constexpr uint32_t K[]
    = { 0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf,
	0x4787c62a, 0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af,
	0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e,
	0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
	0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6,
	0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
	0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122,
	0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
	0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039,
	0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244, 0x432aff97,
	0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d,
	0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
	0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391 };

  static constexpr int S[]
    = { 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
	5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20,
	4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
	6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21 };

  std::array<uint32_t, 16> M;
  for (int i = 0; i < 16; ++i)
    M[i] = static_cast<uint32_t> (block[i * 4])
	   | (static_cast<uint32_t> (block[i * 4 + 1]) << 8)
	   | (static_cast<uint32_t> (block[i * 4 + 2]) << 16)
	   | (static_cast<uint32_t> (block[i * 4 + 3]) << 24);

  uint32_t a = state_[0];
  uint32_t b = state_[1];
  uint32_t c = state_[2];
  uint32_t d = state_[3];

  for (int i = 0; i < 64; ++i)
    {
      uint32_t f, g;
      if (i < 16)
	{
	  f = (b & c) | (~b & d);
	  g = i;
	}
      else if (i < 32)
	{
	  f = (d & b) | (~d & c);
	  g = (5 * i + 1) % 16;
	}
      else if (i < 48)
	{
	  f = b ^ c ^ d;
	  g = (3 * i + 5) % 16;
	}
      else
	{
	  f = c ^ (b | ~d);
	  g = (7 * i) % 16;
	}
      f = f + a + K[i] + M[g];
      a = d;
      d = c;
      c = b;
      b = b + detail::rotate_left (f, S[i]);
    }

  state_[0] += a;
  state_[1] += b;
  state_[2] += c;
  state_[3] += d;
}

inline void
md5_context::finalize (md5_digest &digest) noexcept
{
  uint64_t bits = count_ * 8;

  uint8_t pad = 0x80;
  update (&pad, 1);

  while (buffer_len_ != 56)
    {
      pad = 0x00;
      update (&pad, 1);
    }

  uint8_t len_bytes[8];
  for (int i = 0; i < 8; ++i)
    len_bytes[i] = static_cast<uint8_t> (bits >> (i * 8));
  update (len_bytes, 8);

  for (int i = 0; i < 4; ++i)
    {
      digest[i * 4] = static_cast<uint8_t> (state_[i]);
      digest[i * 4 + 1] = static_cast<uint8_t> (state_[i] >> 8);
      digest[i * 4 + 2] = static_cast<uint8_t> (state_[i] >> 16);
      digest[i * 4 + 3] = static_cast<uint8_t> (state_[i] >> 24);
    }
}

inline void
sha1_context::update (const void *data, size_t len) noexcept
{
  const auto *input = static_cast<const uint8_t *> (data);

  while (len > 0)
    {
      size_t to_copy = std::min (len, 64 - buffer_len_);
      std::memcpy (buffer_.data () + buffer_len_, input, to_copy);
      buffer_len_ += to_copy;
      input += to_copy;
      len -= to_copy;
      count_ += to_copy;

      if (buffer_len_ == 64)
	{
	  transform (buffer_.data ());
	  buffer_len_ = 0;
	}
    }
}

inline void
sha1_context::transform (const uint8_t block[64]) noexcept
{
  std::array<uint32_t, 80> W;

  for (int i = 0; i < 16; ++i)
    W[i] = (static_cast<uint32_t> (block[i * 4]) << 24)
	   | (static_cast<uint32_t> (block[i * 4 + 1]) << 16)
	   | (static_cast<uint32_t> (block[i * 4 + 2]) << 8)
	   | static_cast<uint32_t> (block[i * 4 + 3]);

  for (int i = 16; i < 80; ++i)
    W[i] = detail::rotate_left (W[i - 3] ^ W[i - 8] ^ W[i - 14]
				  ^ W[i - 16],
				1);

  uint32_t a = state_[0];
  uint32_t b = state_[1];
  uint32_t c = state_[2];
  uint32_t d = state_[3];
  uint32_t e = state_[4];

  for (int i = 0; i < 80; ++i)
    {
      uint32_t f, k;
      if (i < 20)
	{
	  f = (b & c) | (~b & d);
	  k = 0x5a827999;
	}
      else if (i < 40)
	{
	  f = b ^ c ^ d;
	  k = 0x6ed9eba1;
	}
      else if (i < 60)
	{
	  f = (b & c) | (b & d) | (c & d);
	  k = 0x8f1bbcdc;
	}
      else
	{
	  f = b ^ c ^ d;
	  k = 0xca62c1d6;
	}
      uint32_t temp = detail::rotate_left (a, 5) + f + e + k + W[i];
      e = d;
      d = c;
      c = detail::rotate_left (b, 30);
      b = a;
      a = temp;
    }

  state_[0] += a;
  state_[1] += b;
  state_[2] += c;
  state_[3] += d;
  state_[4] += e;
}

inline void
sha1_context::finalize (sha1_digest &digest) noexcept
{
  uint64_t bits = count_ * 8;

  uint8_t pad = 0x80;
  update (&pad, 1);

  while (buffer_len_ != 56)
    {
      pad = 0x00;
      update (&pad, 1);
    }

  uint8_t len_bytes[8];
  for (int i = 0; i < 8; ++i)
    len_bytes[i] = static_cast<uint8_t> (bits >> ((7 - i) * 8));
  update (len_bytes, 8);

  for (int i = 0; i < 5; ++i)
    {
      digest[i * 4] = static_cast<uint8_t> (state_[i] >> 24);
      digest[i * 4 + 1] = static_cast<uint8_t> (state_[i] >> 16);
      digest[i * 4 + 2] = static_cast<uint8_t> (state_[i] >> 8);
      digest[i * 4 + 3] = static_cast<uint8_t> (state_[i]);
    }
}

[[nodiscard]] inline md5_digest
md5 (const void *data, size_t len) noexcept
{
  md5_context ctx;
  ctx.update (data, len);
  return ctx.finalize ();
}

[[nodiscard]] inline md5_digest
md5 (std::string_view data) noexcept
{
  return md5 (data.data (), data.size ());
}

[[nodiscard]] inline sha1_digest
sha1 (const void *data, size_t len) noexcept
{
  sha1_context ctx;
  ctx.update (data, len);
  return ctx.finalize ();
}

[[nodiscard]] inline sha1_digest
sha1 (std::string_view data) noexcept
{
  return sha1 (data.data (), data.size ());
}

template <size_t N>
[[nodiscard]] inline std::string
digest_to_hex (const std::array<uint8_t, N> &digest)
{
  std::ostringstream oss;
  oss << std::hex << std::setfill ('0');
  for (uint8_t byte : digest)
    oss << std::setw (2) << static_cast<int> (byte);
  return oss.str ();
}

[[nodiscard]] inline std::string
md5_hex (const void *data, size_t len)
{
  return digest_to_hex (md5 (data, len));
}

[[nodiscard]] inline std::string
md5_hex (std::string_view data)
{
  return digest_to_hex (md5 (data));
}

[[nodiscard]] inline std::string
sha1_hex (const void *data, size_t len)
{
  return digest_to_hex (sha1 (data, len));
}

[[nodiscard]] inline std::string
sha1_hex (std::string_view data)
{
  return digest_to_hex (sha1 (data));
}

class sha256_context
{
public:
  sha256_context () noexcept { reset (); }

  void reset () noexcept
  {
    state_[0] = 0x6a09e667;
    state_[1] = 0xbb67ae85;
    state_[2] = 0x3c6ef372;
    state_[3] = 0xa54ff53a;
    state_[4] = 0x510e527f;
    state_[5] = 0x9b05688c;
    state_[6] = 0x1f83d9ab;
    state_[7] = 0x5be0cd19;
    count_ = 0;
    buffer_len_ = 0;
  }

  void update (const void *data, size_t len) noexcept;
  void finalize (sha256_digest &digest) noexcept;

  [[nodiscard]] sha256_digest finalize () noexcept
  {
    sha256_digest result;
    finalize (result);
    return result;
  }

private:
  void transform (const uint8_t block[64]) noexcept;

  std::array<uint32_t, 8> state_;
  uint64_t count_;
  std::array<uint8_t, 64> buffer_;
  size_t buffer_len_;
};

inline void
sha256_context::update (const void *data, size_t len) noexcept
{
  const auto *input = static_cast<const uint8_t *> (data);

  while (len > 0)
    {
      size_t to_copy = std::min (len, 64 - buffer_len_);
      std::memcpy (buffer_.data () + buffer_len_, input, to_copy);
      buffer_len_ += to_copy;
      input += to_copy;
      len -= to_copy;
      count_ += to_copy;

      if (buffer_len_ == 64)
	{
	  transform (buffer_.data ());
	  buffer_len_ = 0;
	}
    }
}

inline void
sha256_context::transform (const uint8_t block[64]) noexcept
{
  static constexpr uint32_t K[64]
    = { 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b,
	0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
	0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7,
	0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
	0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152,
	0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
	0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
	0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819,
	0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
	0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f,
	0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
	0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 };

  std::array<uint32_t, 64> W;

  for (int i = 0; i < 16; ++i)
    W[i] = (static_cast<uint32_t> (block[i * 4]) << 24)
	   | (static_cast<uint32_t> (block[i * 4 + 1]) << 16)
	   | (static_cast<uint32_t> (block[i * 4 + 2]) << 8)
	   | static_cast<uint32_t> (block[i * 4 + 3]);

  for (int i = 16; i < 64; ++i)
    {
      uint32_t s0 = detail::rotate_right (W[i - 15], 7)
		    ^ detail::rotate_right (W[i - 15], 18)
		    ^ (W[i - 15] >> 3);
      uint32_t s1 = detail::rotate_right (W[i - 2], 17)
		    ^ detail::rotate_right (W[i - 2], 19)
		    ^ (W[i - 2] >> 10);
      W[i] = W[i - 16] + s0 + W[i - 7] + s1;
    }

  uint32_t a = state_[0], b = state_[1], c = state_[2], d = state_[3];
  uint32_t e = state_[4], f = state_[5], g = state_[6], h = state_[7];

  for (int i = 0; i < 64; ++i)
    {
      uint32_t S1 = detail::rotate_right (e, 6)
		    ^ detail::rotate_right (e, 11)
		    ^ detail::rotate_right (e, 25);
      uint32_t ch = (e & f) ^ (~e & g);
      uint32_t temp1 = h + S1 + ch + K[i] + W[i];
      uint32_t S0 = detail::rotate_right (a, 2)
		    ^ detail::rotate_right (a, 13)
		    ^ detail::rotate_right (a, 22);
      uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
      uint32_t temp2 = S0 + maj;

      h = g;
      g = f;
      f = e;
      e = d + temp1;
      d = c;
      c = b;
      b = a;
      a = temp1 + temp2;
    }

  state_[0] += a;
  state_[1] += b;
  state_[2] += c;
  state_[3] += d;
  state_[4] += e;
  state_[5] += f;
  state_[6] += g;
  state_[7] += h;
}

inline void
sha256_context::finalize (sha256_digest &digest) noexcept
{
  uint64_t bits = count_ * 8;

  uint8_t pad = 0x80;
  update (&pad, 1);

  while (buffer_len_ != 56)
    {
      pad = 0x00;
      update (&pad, 1);
    }

  uint8_t len_bytes[8];
  for (int i = 0; i < 8; ++i)
    len_bytes[i] = static_cast<uint8_t> (bits >> ((7 - i) * 8));
  update (len_bytes, 8);

  for (int i = 0; i < 8; ++i)
    {
      digest[i * 4] = static_cast<uint8_t> (state_[i] >> 24);
      digest[i * 4 + 1] = static_cast<uint8_t> (state_[i] >> 16);
      digest[i * 4 + 2] = static_cast<uint8_t> (state_[i] >> 8);
      digest[i * 4 + 3] = static_cast<uint8_t> (state_[i]);
    }
}

class sha512_context
{
public:
  sha512_context () noexcept { reset (); }

  void reset () noexcept
  {
    state_[0] = 0x6a09e667f3bcc908ULL;
    state_[1] = 0xbb67ae8584caa73bULL;
    state_[2] = 0x3c6ef372fe94f82bULL;
    state_[3] = 0xa54ff53a5f1d36f1ULL;
    state_[4] = 0x510e527fade682d1ULL;
    state_[5] = 0x9b05688c2b3e6c1fULL;
    state_[6] = 0x1f83d9abfb41bd6bULL;
    state_[7] = 0x5be0cd19137e2179ULL;
    count_lo_ = 0;
    count_hi_ = 0;
    buffer_len_ = 0;
  }

  void update (const void *data, size_t len) noexcept;
  void finalize (sha512_digest &digest) noexcept;

  [[nodiscard]] sha512_digest finalize () noexcept
  {
    sha512_digest result;
    finalize (result);
    return result;
  }

private:
  void transform (const uint8_t block[128]) noexcept;

  std::array<uint64_t, 8> state_;
  uint64_t count_lo_;
  uint64_t count_hi_;
  std::array<uint8_t, 128> buffer_;
  size_t buffer_len_;
};

inline void
sha512_context::update (const void *data, size_t len) noexcept
{
  const auto *input = static_cast<const uint8_t *> (data);

  while (len > 0)
    {
      size_t to_copy
	= std::min (len, static_cast<size_t> (128 - buffer_len_));
      std::memcpy (buffer_.data () + buffer_len_, input, to_copy);
      buffer_len_ += to_copy;
      input += to_copy;
      len -= to_copy;

      uint64_t old_lo = count_lo_;
      count_lo_ += to_copy;
      if (count_lo_ < old_lo)
	++count_hi_;

      if (buffer_len_ == 128)
	{
	  transform (buffer_.data ());
	  buffer_len_ = 0;
	}
    }
}

inline void
sha512_context::transform (const uint8_t block[128]) noexcept
{
  static constexpr uint64_t K[80]
    = { 0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL,
	0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
	0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL,
	0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
	0xd807aa98a3030242ULL, 0x12835b0145706fbeULL,
	0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
	0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL,
	0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
	0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL,
	0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
	0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL,
	0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
	0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL,
	0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
	0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL,
	0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
	0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL,
	0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
	0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL,
	0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
	0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL,
	0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
	0xd192e819d6ef5218ULL, 0xd69906245565a910ULL,
	0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
	0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL,
	0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
	0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL,
	0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
	0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL,
	0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
	0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL,
	0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
	0xca273eceea26619cULL, 0xd186b8c721c0c207ULL,
	0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
	0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL,
	0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
	0x28db77f523047d84ULL, 0x32caab7b40c72493ULL,
	0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
	0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL,
	0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL };

  std::array<uint64_t, 80> W;

  for (int i = 0; i < 16; ++i)
    W[i] = (static_cast<uint64_t> (block[i * 8]) << 56)
	   | (static_cast<uint64_t> (block[i * 8 + 1]) << 48)
	   | (static_cast<uint64_t> (block[i * 8 + 2]) << 40)
	   | (static_cast<uint64_t> (block[i * 8 + 3]) << 32)
	   | (static_cast<uint64_t> (block[i * 8 + 4]) << 24)
	   | (static_cast<uint64_t> (block[i * 8 + 5]) << 16)
	   | (static_cast<uint64_t> (block[i * 8 + 6]) << 8)
	   | static_cast<uint64_t> (block[i * 8 + 7]);

  for (int i = 16; i < 80; ++i)
    {
      uint64_t s0 = detail::rotate_right64 (W[i - 15], 1)
		    ^ detail::rotate_right64 (W[i - 15], 8)
		    ^ (W[i - 15] >> 7);
      uint64_t s1 = detail::rotate_right64 (W[i - 2], 19)
		    ^ detail::rotate_right64 (W[i - 2], 61)
		    ^ (W[i - 2] >> 6);
      W[i] = W[i - 16] + s0 + W[i - 7] + s1;
    }

  uint64_t a = state_[0], b = state_[1], c = state_[2], d = state_[3];
  uint64_t e = state_[4], f = state_[5], g = state_[6], h = state_[7];

  for (int i = 0; i < 80; ++i)
    {
      uint64_t S1 = detail::rotate_right64 (e, 14)
		    ^ detail::rotate_right64 (e, 18)
		    ^ detail::rotate_right64 (e, 41);
      uint64_t ch = (e & f) ^ (~e & g);
      uint64_t temp1 = h + S1 + ch + K[i] + W[i];
      uint64_t S0 = detail::rotate_right64 (a, 28)
		    ^ detail::rotate_right64 (a, 34)
		    ^ detail::rotate_right64 (a, 39);
      uint64_t maj = (a & b) ^ (a & c) ^ (b & c);
      uint64_t temp2 = S0 + maj;

      h = g;
      g = f;
      f = e;
      e = d + temp1;
      d = c;
      c = b;
      b = a;
      a = temp1 + temp2;
    }

  state_[0] += a;
  state_[1] += b;
  state_[2] += c;
  state_[3] += d;
  state_[4] += e;
  state_[5] += f;
  state_[6] += g;
  state_[7] += h;
}

inline void
sha512_context::finalize (sha512_digest &digest) noexcept
{
  uint64_t bits_lo = count_lo_ * 8;
  uint64_t bits_hi = count_hi_ * 8 + (count_lo_ >> 61);

  uint8_t pad = 0x80;
  update (&pad, 1);

  while (buffer_len_ != 112)
    {
      pad = 0x00;
      update (&pad, 1);
    }

  uint8_t len_bytes[16];
  for (int i = 0; i < 8; ++i)
    {
      len_bytes[i] = static_cast<uint8_t> (bits_hi >> ((7 - i) * 8));
      len_bytes[i + 8]
	= static_cast<uint8_t> (bits_lo >> ((7 - i) * 8));
    }
  update (len_bytes, 16);

  for (int i = 0; i < 8; ++i)
    {
      digest[i * 8] = static_cast<uint8_t> (state_[i] >> 56);
      digest[i * 8 + 1] = static_cast<uint8_t> (state_[i] >> 48);
      digest[i * 8 + 2] = static_cast<uint8_t> (state_[i] >> 40);
      digest[i * 8 + 3] = static_cast<uint8_t> (state_[i] >> 32);
      digest[i * 8 + 4] = static_cast<uint8_t> (state_[i] >> 24);
      digest[i * 8 + 5] = static_cast<uint8_t> (state_[i] >> 16);
      digest[i * 8 + 6] = static_cast<uint8_t> (state_[i] >> 8);
      digest[i * 8 + 7] = static_cast<uint8_t> (state_[i]);
    }
}

[[nodiscard]] inline sha256_digest
sha256 (const void *data, size_t len) noexcept
{
  sha256_context ctx;
  ctx.update (data, len);
  return ctx.finalize ();
}

[[nodiscard]] inline sha256_digest
sha256 (std::string_view data) noexcept
{
  return sha256 (data.data (), data.size ());
}

[[nodiscard]] inline sha512_digest
sha512 (const void *data, size_t len) noexcept
{
  sha512_context ctx;
  ctx.update (data, len);
  return ctx.finalize ();
}

[[nodiscard]] inline sha512_digest
sha512 (std::string_view data) noexcept
{
  return sha512 (data.data (), data.size ());
}

[[nodiscard]] inline std::string
sha256_hex (const void *data, size_t len)
{
  return digest_to_hex (sha256 (data, len));
}

[[nodiscard]] inline std::string
sha256_hex (std::string_view data)
{
  return digest_to_hex (sha256 (data));
}

[[nodiscard]] inline std::string
sha512_hex (const void *data, size_t len)
{
  return digest_to_hex (sha512 (data, len));
}

[[nodiscard]] inline std::string
sha512_hex (std::string_view data)
{
  return digest_to_hex (sha512 (data));
}

}
