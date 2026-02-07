#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string_view>

#if defined(__clang__)
# pragma clang diagnostic push
# pragma clang diagnostic ignored "-Wreturn-type-c-linkage"
# pragma clang diagnostic ignored "-Wunused-parameter"
# pragma clang diagnostic ignored "-Wnested-anon-types"
#endif

#include "containers.hpp"
#include "input_parser.hpp"

#if defined(__clang__)
# pragma clang diagnostic pop
#endif

namespace emacs
{

struct KeyStroke
{
  tui::KeyCode key;
  tui::KeyModifier modifiers;
  uint32_t unicode;

  bool operator== (const KeyStroke &other) const noexcept;
};

struct KeyStrokeHash
{
  size_t operator() (const KeyStroke &ks) const noexcept;
};

using KeySequence = gc_vector_t<KeyStroke>;

[[nodiscard]] KeyStroke
make_keystroke (tui::KeyCode key, tui::KeyModifier mods
				  = tui::KeyModifier::None) noexcept;

[[nodiscard]] KeyStroke make_char_keystroke (char c) noexcept;

[[nodiscard]] KeyStroke make_ctrl_keystroke (char c) noexcept;

enum class KeyLookupType : uint8_t
{
  Unbound,
  Command,
  PrefixKey,
};

struct KeyLookupResult
{
  KeyLookupType type;
  gc_string command_name;
};

class Keymap
{
public:
  explicit Keymap (std::string_view name);

  void bind (const KeyStroke &ks, std::string_view command);

  void bind_sequence (const KeySequence &seq,
		      std::string_view command);

  [[nodiscard]] KeyLookupResult
  lookup (const KeyStroke &ks) const noexcept;

  [[nodiscard]] KeyLookupResult
  lookup_sequence (const KeySequence &seq) const noexcept;

  [[nodiscard]] bool is_prefix (const KeyStroke &ks) const noexcept;

  [[nodiscard]] const Keymap *
  get_prefix_keymap (const KeyStroke &ks) const noexcept;

  [[nodiscard]] Keymap *
  get_or_create_prefix_keymap (const KeyStroke &ks);

  void unbind (const KeyStroke &ks);

  [[nodiscard]] const gc_string &name () const noexcept;

  void set_parent (const Keymap *parent) noexcept;

  [[nodiscard]] const Keymap *parent () const noexcept;

private:
  gc_string name_;
  const Keymap *parent_ = nullptr;

  struct Binding
  {
    bool is_prefix = false;
    gc_string command;
    std::unique_ptr<Keymap> sub_keymap;
  };

  gc_unordered_map<KeyStroke, Binding, KeyStrokeHash> bindings_;
};

class KeymapManager
{
public:
  static KeymapManager &instance () noexcept;

  [[nodiscard]] Keymap &global_keymap () noexcept;

  void set_major_mode_keymap (const Keymap *km) noexcept;

  void push_minor_mode_keymap (const Keymap *km);

  void remove_minor_mode_keymap (const Keymap *km);

  void set_local_keymap (const Keymap *km) noexcept;

  [[nodiscard]] KeyLookupResult
  lookup (const KeyStroke &ks) const noexcept;

  [[nodiscard]] KeyLookupResult
  lookup_sequence (const KeySequence &seq) const noexcept;

  void clear () noexcept;

private:
  KeymapManager ();

  Keymap global_keymap_;
  const Keymap *major_mode_keymap_ = nullptr;
  gc_vector_t<const Keymap *> minor_mode_keymaps_;
  const Keymap *local_keymap_ = nullptr;
};

} // namespace emacs

extern "C"
{
  int emacs_cxx_keymap_bind (const char *keymap_name, int key_code,
			     int modifiers, const char *command);
  int emacs_cxx_keymap_lookup (int key_code, int modifiers,
			       char *out_command, int out_len);
}
