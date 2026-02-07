#pragma once

#include <cstdint>
#include <functional>
#include <string_view>

#include "containers.hpp"
#include "emacs_keymap.hpp"

namespace emacs
{

class EmacsBuffer;

enum class ModeType : uint8_t
{
  Major,
  Minor,
};

using ModeHook = std::function<void ()>;

struct ModeDefinition
{
  gc_string name;
  ModeType type;
  gc_string docstring;
  Keymap keymap;
  gc_vector_t<ModeHook> enable_hooks;
  gc_vector_t<ModeHook> disable_hooks;
  gc_string parent_name;

  ModeDefinition (std::string_view mode_name, ModeType mode_type,
		  std::string_view doc, std::string_view parent);

  ModeDefinition () = delete;
  ModeDefinition (const ModeDefinition &) = delete;
  ModeDefinition &operator= (const ModeDefinition &) = delete;
  ModeDefinition (ModeDefinition &&) noexcept = default;
  ModeDefinition &operator= (ModeDefinition &&) noexcept = default;
};

class ModeManager
{
public:
  static ModeManager &instance () noexcept;

  void define_major_mode (std::string_view name,
			  std::string_view docstring,
			  std::string_view parent_name = "");

  void define_minor_mode (std::string_view name,
			  std::string_view docstring);

  [[nodiscard]] Keymap &mode_keymap (std::string_view name);

  void activate_major_mode (std::string_view name,
			    EmacsBuffer *buffer);

  void enable_minor_mode (std::string_view name, EmacsBuffer *buffer);

  void disable_minor_mode (std::string_view name,
			   EmacsBuffer *buffer);

  [[nodiscard]] const gc_string &current_major_mode () const noexcept;

  [[nodiscard]] bool
  minor_mode_enabled (std::string_view name) const noexcept;

  [[nodiscard]] gc_vector_t<gc_string> active_minor_modes () const;

  [[nodiscard]] bool has_mode (std::string_view name) const noexcept;

  void add_mode_hook (std::string_view mode_name, ModeHook hook,
		      bool enable = true);

  void reset ();

private:
  ModeManager ();

  [[nodiscard]] ModeDefinition *
  find_mode (std::string_view name) noexcept;

  [[nodiscard]] const ModeDefinition *
  find_mode (std::string_view name) const noexcept;

  void ensure_parent_keymap (ModeDefinition &mode);
  void init_fundamental_mode ();

  gc_unordered_map<gc_string, ModeDefinition> modes_;
  gc_string current_major_mode_;
  gc_vector_t<gc_string> active_minor_modes_;
};

} // namespace emacs

extern "C"
{
  int emacs_cxx_activate_major_mode (const char *name);
  int emacs_cxx_enable_minor_mode (const char *name);
  int emacs_cxx_disable_minor_mode (const char *name);
  const char *emacs_cxx_current_major_mode ();
}
