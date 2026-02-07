// src/sdl2_term.hpp
#pragma once

#ifdef EMACS_USE_SDL2

# include <concepts>
# include <cstdint>
# include <memory>
# include <span>
# include <string>
# include <string_view>
# include <utility>

# include "containers.hpp"
# include "terminal_concept.hpp"

// Forward declare SDL types to avoid including SDL.h in header
struct SDL_Window;
struct SDL_Renderer;
struct _TTF_Font;
typedef struct _TTF_Font TTF_Font;
struct SDL_Texture;
union SDL_Event;

namespace emacs
{

class SDL2Backend
{
private:
  bool initialized_;
  SDL_Window *window_;
  SDL_Renderer *renderer_;
  TTF_Font *font_;
  SDL_Texture *glyph_atlas_;

  int window_width_;
  int window_height_;
  int cell_width_;
  int cell_height_;
  int rows_;
  int cols_;

  CursorPosition cursor_;
  bool raw_mode_;

  struct GlyphCacheEntry
  {
    SDL_Texture *texture;
    int width;
    int height;
  };

  gc_unordered_map<uint64_t, GlyphCacheEntry> glyph_cache_;

  void render_cell (int row, int col, char32_t codepoint,
		    const TerminalColor &fg, const TerminalColor &bg,
		    bool bold, bool italic, bool underline,
		    bool inverse);
  [[nodiscard]] uint64_t glyph_cache_key (char32_t cp, bool bold,
					  bool italic) const noexcept;
  [[nodiscard]] InputEvent
  translate_sdl_event (const SDL_Event &event) noexcept;

public:
  SDL2Backend () noexcept;
  ~SDL2Backend ();

  SDL2Backend (const SDL2Backend &) = delete;
  SDL2Backend &operator= (const SDL2Backend &) = delete;

  [[nodiscard]] bool init () noexcept;
  void cleanup () noexcept;

  void write_glyphs (std::span<TerminalGlyph> glyphs) noexcept;
  void write_text (std::string_view text) noexcept;
  void clear_to_end (CursorPosition pos) noexcept;
  void clear_frame () noexcept;
  void clear_end_of_line (CursorPosition pos) noexcept;

  void set_cursor_position (CursorPosition pos) noexcept;
  [[nodiscard]] CursorPosition get_cursor_position () const noexcept;

  void insert_glyphs (CursorPosition pos,
		      std::span<TerminalGlyph> glyphs) noexcept;
  void delete_glyphs (CursorPosition pos, std::size_t n) noexcept;
  void insert_lines (CursorPosition pos, std::size_t n) noexcept;
  void delete_lines (CursorPosition pos, std::size_t n) noexcept;

  [[nodiscard]] bool supports_colors () const noexcept;
  [[nodiscard]] bool supports_truecolor () const noexcept;
  [[nodiscard]] bool supports_blinking_cursor () const noexcept;
  [[nodiscard]] bool supports_bracketed_paste () const noexcept;

  [[nodiscard]] std::pair<int, int>
  get_terminal_size () const noexcept;
  [[nodiscard]] InputEvent read_input () noexcept;
  void set_raw_mode (bool raw) noexcept;
  void flush () noexcept;
};

static_assert (TerminalBackend<SDL2Backend>);

} // namespace emacs

#endif // EMACS_USE_SDL2
