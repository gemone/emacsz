// src/gnulib/hmac.hpp
// C++20 replacements for gnulib HMAC utilities
// Replaces: hmac-md5, hmac-sha1, hmac-sha256, hmac-sha512

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "crypto.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <string_view>

namespace emacs::gnulib
{

// Result types (same as underlying hash)
using hmac_md5_digest = md5_digest;	  // 16 bytes
using hmac_sha1_digest = sha1_digest;	  // 20 bytes
using hmac_sha256_digest = sha256_digest; // 32 bytes
using hmac_sha512_digest = sha512_digest; // 64 bytes

namespace detail
{

// HMAC implementation following RFC 2104
// HMAC(K, m) = H((K' ⊕ opad) || H((K' ⊕ ipad) || m))

template <typename HashContext, typename DigestType, size_t BlockSize>
inline DigestType
hmac_impl (const uint8_t *key, size_t key_len, const uint8_t *data,
	   size_t data_len) noexcept
{
  std::array<uint8_t, BlockSize> key_padded = {};

  if (key_len > BlockSize)
    {
      HashContext ctx;
      ctx.update (key, key_len);
      auto hashed = ctx.finalize ();
      std::memcpy (key_padded.data (), hashed.data (),
		   hashed.size ());
    }
  else
    {
      std::memcpy (key_padded.data (), key, key_len);
    }

  std::array<uint8_t, BlockSize> ipad = {};
  std::array<uint8_t, BlockSize> opad = {};

  for (size_t i = 0; i < BlockSize; ++i)
    {
      ipad[i] = key_padded[i] ^ 0x36;
      opad[i] = key_padded[i] ^ 0x5c;
    }

  HashContext inner_ctx;
  inner_ctx.update (ipad.data (), ipad.size ());
  inner_ctx.update (data, data_len);
  auto inner_hash = inner_ctx.finalize ();

  HashContext outer_ctx;
  outer_ctx.update (opad.data (), opad.size ());
  outer_ctx.update (inner_hash.data (), inner_hash.size ());
  return outer_ctx.finalize ();
}

} // namespace detail

[[nodiscard]] inline hmac_md5_digest
hmac_md5 (const void *key, size_t key_len, const void *data,
	  size_t data_len) noexcept
{
  return detail::hmac_impl<md5_context, hmac_md5_digest,
			   64> (static_cast<const uint8_t *> (key),
				key_len,
				static_cast<const uint8_t *> (data),
				data_len);
}

[[nodiscard]] inline hmac_sha1_digest
hmac_sha1 (const void *key, size_t key_len, const void *data,
	   size_t data_len) noexcept
{
  return detail::hmac_impl<sha1_context, hmac_sha1_digest,
			   64> (static_cast<const uint8_t *> (key),
				key_len,
				static_cast<const uint8_t *> (data),
				data_len);
}

[[nodiscard]] inline hmac_sha256_digest
hmac_sha256 (const void *key, size_t key_len, const void *data,
	     size_t data_len) noexcept
{
  return detail::hmac_impl<sha256_context, hmac_sha256_digest,
			   64> (static_cast<const uint8_t *> (key),
				key_len,
				static_cast<const uint8_t *> (data),
				data_len);
}

[[nodiscard]] inline hmac_sha512_digest
hmac_sha512 (const void *key, size_t key_len, const void *data,
	     size_t data_len) noexcept
{
  return detail::hmac_impl<sha512_context, hmac_sha512_digest,
			   128> (static_cast<const uint8_t *> (key),
				 key_len,
				 static_cast<const uint8_t *> (data),
				 data_len);
}

[[nodiscard]] inline hmac_md5_digest
hmac_md5 (std::string_view key, std::string_view data) noexcept
{
  return hmac_md5 (key.data (), key.size (), data.data (),
		   data.size ());
}

[[nodiscard]] inline hmac_sha1_digest
hmac_sha1 (std::string_view key, std::string_view data) noexcept
{
  return hmac_sha1 (key.data (), key.size (), data.data (),
		    data.size ());
}

[[nodiscard]] inline hmac_sha256_digest
hmac_sha256 (std::string_view key, std::string_view data) noexcept
{
  return hmac_sha256 (key.data (), key.size (), data.data (),
		      data.size ());
}

[[nodiscard]] inline hmac_sha512_digest
hmac_sha512 (std::string_view key, std::string_view data) noexcept
{
  return hmac_sha512 (key.data (), key.size (), data.data (),
		      data.size ());
}

[[nodiscard]] inline std::string
hmac_md5_hex (std::string_view key, std::string_view data)
{
  return digest_to_hex (hmac_md5 (key, data));
}

[[nodiscard]] inline std::string
hmac_sha1_hex (std::string_view key, std::string_view data)
{
  return digest_to_hex (hmac_sha1 (key, data));
}

[[nodiscard]] inline std::string
hmac_sha256_hex (std::string_view key, std::string_view data)
{
  return digest_to_hex (hmac_sha256 (key, data));
}

[[nodiscard]] inline std::string
hmac_sha512_hex (std::string_view key, std::string_view data)
{
  return digest_to_hex (hmac_sha512 (key, data));
}

} // namespace emacs::gnulib
