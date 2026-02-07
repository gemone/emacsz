// src/sdl2_term.cpp
#ifdef EMACS_USE_SDL2

# include "sdl2_term.hpp"

# include <SDL.h>
# include <SDL_ttf.h>

# include <algorithm>
# include <cerrno>
# include <cstring>
# include <iostream>

namespace emacs
{

namespace
{

[[nodiscard]] SDL_Color
to_sdl_color (const TerminalColor &color) noexcept
{
  SDL_Color result;
  result.r = color.red;
  result.g = color.green;
  result.b = color.blue;
  result.a = 255;
  return result;
}

[[nodiscard]] const char *
resolve_font_path ()
{
  const char *env_path = std::getenv ("EMACS_FONT_PATH");
  if (env_path && std::strlen (env_path) > 0)
    return env_path;

  static const char *paths[]
    = { "/System/Library/Fonts/Menlo.ttc",
	"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
	"C:\\Windows\\Fonts\\consola.ttf" };

  for (const auto *path : paths)
    {
      SDL_RWops *ops = SDL_RWFromFile (path, "rb");
      if (ops)
	{
	  SDL_RWclose (ops);
	  return path;
	}
    }

  return nullptr;
}

[[nodiscard]] uint8_t
mods_from_sdl (SDL_Keymod mod) noexcept
{
  uint8_t result = 0;
  if (mod & KMOD_SHIFT)
    result |= 0x01;
  if (mod & KMOD_CTRL)
    result |= 0x02;
  if (mod & KMOD_ALT)
    result |= 0x04;
  if (mod & KMOD_GUI)
    result |= 0x08;
  return result;
}

} // namespace

SDL2Backend::SDL2Backend () noexcept
    : initialized_ (false), window_ (nullptr), renderer_ (nullptr),
      font_ (nullptr), glyph_atlas_ (nullptr), window_width_ (0),
      window_height_ (0), cell_width_ (0), cell_height_ (0),
      rows_ (0), cols_ (0), cursor_{ 0, 0 }, raw_mode_ (false)
{
}

SDL2Backend::~SDL2Backend () { cleanup (); }

[[nodiscard]] bool
SDL2Backend::init () noexcept
{
  if (SDL_Init (SDL_INIT_VIDEO) != 0)
    {
      std::cerr << "SDL_Init failed: " << SDL_GetError () << "\n";
      return false;
    }

  if (TTF_Init () != 0)
    {
      std::cerr << "TTF_Init failed: " << TTF_GetError () << "\n";
      SDL_Quit ();
      return false;
    }

  window_
    = SDL_CreateWindow ("Emacs", SDL_WINDOWPOS_CENTERED,
			SDL_WINDOWPOS_CENTERED, 1024, 768,
			SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
  if (!window_)
    {
      std::cerr << "SDL_CreateWindow failed: " << SDL_GetError ()
		<< "\n";
      TTF_Quit ();
      SDL_Quit ();
      return false;
    }

  renderer_ = SDL_CreateRenderer (window_, -1,
				  SDL_RENDERER_ACCELERATED
				    | SDL_RENDERER_PRESENTVSYNC);
  if (!renderer_)
    {
      std::cerr << "SDL_CreateRenderer failed: " << SDL_GetError ()
		<< "\n";
      SDL_DestroyWindow (window_);
      window_ = nullptr;
      TTF_Quit ();
      SDL_Quit ();
      return false;
    }

  const char *font_path = resolve_font_path ();
  if (!font_path)
    {
      std::cerr << "SDL2Backend: no font found\n";
      SDL_DestroyRenderer (renderer_);
      renderer_ = nullptr;
      SDL_DestroyWindow (window_);
      window_ = nullptr;
      TTF_Quit ();
      SDL_Quit ();
      return false;
    }

  font_ = TTF_OpenFont (font_path, 16);
  if (!font_)
    {
      std::cerr << "TTF_OpenFont failed: " << TTF_GetError () << "\n";
      SDL_DestroyRenderer (renderer_);
      renderer_ = nullptr;
      SDL_DestroyWindow (window_);
      window_ = nullptr;
      TTF_Quit ();
      SDL_Quit ();
      return false;
    }

  if (TTF_SizeText (font_, "M", &cell_width_, &cell_height_) != 0)
    {
      std::cerr << "TTF_SizeText failed: " << TTF_GetError () << "\n";
      cleanup ();
      return false;
    }

  SDL_GetWindowSize (window_, &window_width_, &window_height_);
  cols_ = (cell_width_ > 0) ? (window_width_ / cell_width_) : 0;
  rows_ = (cell_height_ > 0) ? (window_height_ / cell_height_) : 0;

  cursor_ = { 0, 0 };
  raw_mode_ = false;

  SDL_SetRenderDrawColor (renderer_, 0, 0, 0, 255);
  SDL_RenderClear (renderer_);
  SDL_RenderPresent (renderer_);

  initialized_ = true;
  return true;
}

void
SDL2Backend::cleanup () noexcept
{
  if (!initialized_)
    return;

  for (auto &entry : glyph_cache_)
    {
      if (entry.second.texture)
	SDL_DestroyTexture (entry.second.texture);
    }
  glyph_cache_.clear ();

  if (glyph_atlas_)
    {
      SDL_DestroyTexture (glyph_atlas_);
      glyph_atlas_ = nullptr;
    }

  if (font_)
    {
      TTF_CloseFont (font_);
      font_ = nullptr;
    }

  if (renderer_)
    {
      SDL_DestroyRenderer (renderer_);
      renderer_ = nullptr;
    }

  if (window_)
    {
      SDL_DestroyWindow (window_);
      window_ = nullptr;
    }

  TTF_Quit ();
  SDL_Quit ();
  initialized_ = false;
}

void
SDL2Backend::render_cell (int row, int col, char32_t codepoint,
			  const TerminalColor &fg,
			  const TerminalColor &bg, bool bold,
			  bool italic, bool underline, bool inverse)
{
  if (!initialized_ || !renderer_ || !font_)
    return;

  int x = col * cell_width_;
  int y = row * cell_height_;
  SDL_Rect cell_rect{ x, y, cell_width_, cell_height_ };

  TerminalColor fg_color = fg;
  TerminalColor bg_color = bg;
  if (inverse)
    std::swap (fg_color, bg_color);

  SDL_SetRenderDrawColor (renderer_, bg_color.red, bg_color.green,
			  bg_color.blue, 255);
  SDL_RenderFillRect (renderer_, &cell_rect);

  int style = TTF_STYLE_NORMAL;
  if (bold)
    style |= TTF_STYLE_BOLD;
  if (italic)
    style |= TTF_STYLE_ITALIC;
  if (underline)
    style |= TTF_STYLE_UNDERLINE;
  TTF_SetFontStyle (font_, style);

  uint64_t key = glyph_cache_key (codepoint, bold, italic);
  auto found = glyph_cache_.find (key);
  SDL_Texture *texture = nullptr;
  int glyph_w = 0;
  int glyph_h = 0;

  if (found != glyph_cache_.end ())
    {
      texture = found->second.texture;
      glyph_w = found->second.width;
      glyph_h = found->second.height;
    }
  else
    {
      SDL_Color color = to_sdl_color (fg_color);
      SDL_Surface *surface
	= TTF_RenderGlyph32_Blended (font_, codepoint, color);
      if (!surface)
	return;

      texture = SDL_CreateTextureFromSurface (renderer_, surface);
      glyph_w = surface->w;
      glyph_h = surface->h;
      SDL_FreeSurface (surface);
      if (!texture)
	return;

      glyph_cache_[key] = { texture, glyph_w, glyph_h };
    }

  SDL_SetTextureColorMod (texture, fg_color.red, fg_color.green,
			  fg_color.blue);
  SDL_Rect dst{ x, y, glyph_w, glyph_h };
  SDL_RenderCopy (renderer_, texture, nullptr, &dst);
}

[[nodiscard]] uint64_t
SDL2Backend::glyph_cache_key (char32_t cp, bool bold,
			      bool italic) const noexcept
{
  uint64_t key = static_cast<uint64_t> (cp);
  key |= static_cast<uint64_t> (bold ? 1 : 0) << 32;
  key |= static_cast<uint64_t> (italic ? 1 : 0) << 33;
  return key;
}

[[nodiscard]] InputEvent
SDL2Backend::translate_sdl_event (const SDL_Event &event) noexcept
{
  InputEvent result;
  switch (event.type)
    {
    case SDL_KEYDOWN:
      result.type = InputEventType::Key;
      result.key = static_cast<uint32_t> (event.key.keysym.sym);
      result.ch = static_cast<uint32_t> (event.key.keysym.sym);
      result.mod = mods_from_sdl (
	static_cast<SDL_Keymod> (event.key.keysym.mod));
      break;

    case SDL_TEXTINPUT:
      result.type = InputEventType::Key;
      if (event.text.text[0] != '\0')
	result.ch = static_cast<uint8_t> (event.text.text[0]);
      break;

    case SDL_MOUSEBUTTONDOWN:
    case SDL_MOUSEBUTTONUP:
      result.type = InputEventType::Mouse;
      result.x = event.button.x;
      result.y = event.button.y;
      switch (event.button.button)
	{
	case SDL_BUTTON_LEFT:
	  result.button = MouseButton::Left;
	  break;
	case SDL_BUTTON_RIGHT:
	  result.button = MouseButton::Right;
	  break;
	case SDL_BUTTON_MIDDLE:
	  result.button = MouseButton::Middle;
	  break;
	default:
	  result.button = MouseButton::None;
	  break;
	}
      if (event.type == SDL_MOUSEBUTTONUP)
	result.button = MouseButton::Release;
      break;

    case SDL_MOUSEWHEEL:
      result.type = InputEventType::Mouse;
      result.button = (event.wheel.y > 0) ? MouseButton::WheelUp
					  : MouseButton::WheelDown;
      break;

    case SDL_WINDOWEVENT:
      if (event.window.event == SDL_WINDOWEVENT_RESIZED)
	{
	  result.type = InputEventType::Resize;
	  result.w = event.window.data1;
	  result.h = event.window.data2;
	  window_width_ = result.w;
	  window_height_ = result.h;
	  cols_
	    = (cell_width_ > 0) ? (window_width_ / cell_width_) : 0;
	  rows_ = (cell_height_ > 0) ? (window_height_ / cell_height_)
				     : 0;
	}
      break;

    case SDL_QUIT:
      result.type = InputEventType::Key;
      result.key = 3;
      result.ch = 3;
      break;

    default:
      result.type = InputEventType::None;
      break;
    }

  return result;
}

void
SDL2Backend::write_glyphs (std::span<TerminalGlyph> glyphs) noexcept
{
  if (!initialized_)
    return;

  for (const auto &glyph : glyphs)
    {
      if (cursor_.row >= rows_ || cursor_.col >= cols_)
	break;

      render_cell (cursor_.row, cursor_.col, glyph.codepoint,
		   glyph.foreground, glyph.background, glyph.bold,
		   glyph.italic, glyph.underline, glyph.inverse);

      cursor_.col++;
      if (cursor_.col >= cols_)
	{
	  cursor_.col = 0;
	  cursor_.row++;
	}
    }
}

void
SDL2Backend::write_text (std::string_view text) noexcept
{
  if (!initialized_)
    return;

  for (unsigned char ch : text)
    {
      if (cursor_.row >= rows_ || cursor_.col >= cols_)
	break;

      TerminalGlyph glyph{};
      glyph.codepoint = ch;
      glyph.background = { 0, 0, 0 };
      glyph.foreground = { 255, 255, 255 };
      glyph.bold = false;
      glyph.italic = false;
      glyph.underline = false;
      glyph.inverse = false;
      glyph.blink = false;
      render_cell (cursor_.row, cursor_.col, glyph.codepoint,
		   glyph.foreground, glyph.background, false, false,
		   false, false);

      cursor_.col++;
      if (cursor_.col >= cols_)
	{
	  cursor_.col = 0;
	  cursor_.row++;
	}
    }
}

void
SDL2Backend::clear_to_end (CursorPosition pos) noexcept
{
  if (!initialized_ || !renderer_)
    return;

  SDL_SetRenderDrawColor (renderer_, 0, 0, 0, 255);
  for (int row = pos.row; row < rows_; ++row)
    {
      int start_col = (row == pos.row) ? pos.col : 0;
      SDL_Rect rect{ start_col * cell_width_, row * cell_height_,
		     (cols_ - start_col) * cell_width_,
		     cell_height_ };
      SDL_RenderFillRect (renderer_, &rect);
    }
}

void
SDL2Backend::clear_frame () noexcept
{
  if (!initialized_ || !renderer_)
    return;

  SDL_SetRenderDrawColor (renderer_, 0, 0, 0, 255);
  SDL_RenderClear (renderer_);
}

void
SDL2Backend::clear_end_of_line (CursorPosition pos) noexcept
{
  if (!initialized_ || !renderer_)
    return;

  SDL_SetRenderDrawColor (renderer_, 0, 0, 0, 255);
  SDL_Rect rect{ pos.col * cell_width_, pos.row * cell_height_,
		 (cols_ - pos.col) * cell_width_, cell_height_ };
  SDL_RenderFillRect (renderer_, &rect);
}

void
SDL2Backend::set_cursor_position (CursorPosition pos) noexcept
{
  if (!initialized_)
    return;

  cursor_ = pos;
}

[[nodiscard]] CursorPosition
SDL2Backend::get_cursor_position () const noexcept
{
  return cursor_;
}

void
SDL2Backend::insert_glyphs (CursorPosition pos,
			    std::span<TerminalGlyph> glyphs) noexcept
{
  if (!initialized_)
    return;

  cursor_ = pos;
  write_glyphs (glyphs);
}

void
SDL2Backend::delete_glyphs (CursorPosition pos,
			    std::size_t n) noexcept
{
  if (!initialized_)
    return;

  SDL_SetRenderDrawColor (renderer_, 0, 0, 0, 255);
  SDL_Rect rect{ pos.col * cell_width_, pos.row * cell_height_,
		 static_cast<int> (n) * cell_width_, cell_height_ };
  SDL_RenderFillRect (renderer_, &rect);
}

void
SDL2Backend::insert_lines (CursorPosition pos, std::size_t n) noexcept
{
  if (!initialized_ || n == 0)
    return;

  SDL_Rect rect{ 0, pos.row * cell_height_, cols_ * cell_width_,
		 static_cast<int> (n) * cell_height_ };
  SDL_SetRenderDrawColor (renderer_, 0, 0, 0, 255);
  SDL_RenderFillRect (renderer_, &rect);
}

void
SDL2Backend::delete_lines (CursorPosition pos, std::size_t n) noexcept
{
  if (!initialized_ || n == 0)
    return;

  SDL_Rect rect{ 0, pos.row * cell_height_, cols_ * cell_width_,
		 static_cast<int> (n) * cell_height_ };
  SDL_SetRenderDrawColor (renderer_, 0, 0, 0, 255);
  SDL_RenderFillRect (renderer_, &rect);
}

[[nodiscard]] bool
SDL2Backend::supports_colors () const noexcept
{
  return initialized_;
}

[[nodiscard]] bool
SDL2Backend::supports_truecolor () const noexcept
{
  return initialized_;
}

[[nodiscard]] bool
SDL2Backend::supports_blinking_cursor () const noexcept
{
  return initialized_;
}

[[nodiscard]] bool
SDL2Backend::supports_bracketed_paste () const noexcept
{
  return initialized_;
}

[[nodiscard]] std::pair<int, int>
SDL2Backend::get_terminal_size () const noexcept
{
  return { rows_, cols_ };
}

[[nodiscard]] InputEvent
SDL2Backend::read_input () noexcept
{
  InputEvent result;

  if (!initialized_)
    {
      result.type = InputEventType::Error;
      return result;
    }

  SDL_Event event;
  if (SDL_PollEvent (&event) == 0)
    return result;

  return translate_sdl_event (event);
}

void
SDL2Backend::set_raw_mode (bool raw) noexcept
{
  raw_mode_ = raw;
}

void
SDL2Backend::flush () noexcept
{
  if (!initialized_ || !renderer_)
    return;

  SDL_RenderPresent (renderer_);
}

} // namespace emacs

#endif // EMACS_USE_SDL2
