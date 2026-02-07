// src/haikuterm.cpp
#include "haikuterm.hpp"

namespace emacs
{

HaikuBackend::HaikuBackend () noexcept
#ifdef EMACS_USE_HAIKU
    : window_ (nullptr), view_ (nullptr), content_view_ (nullptr),
      initialized_ (false), cursor_{ 0, 0 }
#else
    : initialized_ (false)
#endif
{
}

HaikuBackend::~HaikuBackend () { cleanup (); }

bool
HaikuBackend::init () noexcept
{
#ifdef EMACS_USE_HAIKU
  BRect frame = BRect (0, 0, 800, 600);

  window_
    = new BWindow (frame, "Emacs", B_TITLED_WINDOW,
		   B_CURRENT_WORKSPACE | B_QUIT_ON_WINDOW_CLOSE);
  if (!window_)
    {
      return false;
    }

  view_ = new BView (frame, "MainView", B_FOLLOW_ALL_SIDES,
		     B_WILL_DRAW | B_FULL_UPDATE_ON_RESIZE);
  if (!view_)
    {
      delete window_;
      window_ = nullptr;
      return false;
    }

  content_view_
    = new BView (BRect (0, 0, frame.Width (), frame.Height ()),
		 "ContentView", B_FOLLOW_ALL_SIDES, B_WILL_DRAW);
  if (!content_view_)
    {
      delete view_;
      delete window_;
      view_ = nullptr;
      window_ = nullptr;
      return false;
    }

  view_->AddChild (content_view_);
  window_->AddChild (view_);
  window_->Show ();
  view_->MakeFocus (true);

  initialized_ = true;
  return true;
#else
  return false;
#endif
}

void
HaikuBackend::cleanup () noexcept
{
#ifdef EMACS_USE_HAIKU
  if (window_)
    {
      window_->Lock ();
      window_->Close ();
      window_ = nullptr;
    }

  view_ = nullptr;
  content_view_ = nullptr;
  initialized_ = false;
#endif
}

void
HaikuBackend::write_glyphs (std::span<TerminalGlyph> glyphs) noexcept
{
#ifdef EMACS_USE_HAIKU
  if (!content_view_ || !initialized_)
    {
      return;
    }

  // Haiku-specific glyph rendering implementation
  for (const auto &glyph : glyphs)
    {
      // TODO: Implement BFont-based glyph rendering
      (void) glyph;
    }
#else
  (void) glyphs;
#endif
}

void
HaikuBackend::write_text (std::string_view text) noexcept
{
#ifdef EMACS_USE_HAIKU
  if (!content_view_ || !initialized_)
    {
      return;
    }

  // Haiku-specific text rendering
  (void) text;
#else
  (void) text;
#endif
}

void
HaikuBackend::clear_to_end (CursorPosition pos) noexcept
{
  (void) pos;
}

void
HaikuBackend::clear_frame () noexcept
{
#ifdef EMACS_USE_HAIKU
  if (!content_view_ || !initialized_)
    {
      return;
    }

  rgb_color bg_color;
  bg_color.red = 0;
  bg_color.green = 0;
  bg_color.blue = 0;
  bg_color.alpha = 255;

  content_view_->SetLowColor (bg_color);
  content_view_->FillRect (content_view_->Bounds (), B_SOLID_LOW);
  content_view_->Sync ();
#endif
}

void
HaikuBackend::clear_end_of_line (CursorPosition pos) noexcept
{
  (void) pos;
}

void
HaikuBackend::set_cursor_position (CursorPosition pos) noexcept
{
#ifdef EMACS_USE_HAIKU
  cursor_ = pos;
#else
  (void) pos;
#endif
}

CursorPosition
HaikuBackend::get_cursor_position () const noexcept
{
#ifdef EMACS_USE_HAIKU
  return cursor_;
#else
  return { 0, 0 };
#endif
}

void
HaikuBackend::insert_glyphs (CursorPosition pos,
			     std::span<TerminalGlyph> glyphs) noexcept
{
  (void) pos;
  (void) glyphs;
}

void
HaikuBackend::delete_glyphs (CursorPosition pos,
			     std::size_t n) noexcept
{
  (void) pos;
  (void) n;
}

void
HaikuBackend::insert_lines (CursorPosition pos,
			    std::size_t n) noexcept
{
  (void) pos;
  (void) n;
}

void
HaikuBackend::delete_lines (CursorPosition pos,
			    std::size_t n) noexcept
{
  (void) pos;
  (void) n;
}

bool
HaikuBackend::supports_colors () const noexcept
{
#ifdef EMACS_USE_HAIKU
  return initialized_;
#else
  return false;
#endif
}

bool
HaikuBackend::supports_truecolor () const noexcept
{
#ifdef EMACS_USE_HAIKU
  return initialized_;
#else
  return false;
#endif
}

bool
HaikuBackend::supports_blinking_cursor () const noexcept
{
#ifdef EMACS_USE_HAIKU
  return initialized_;
#else
  return false;
#endif
}

bool
HaikuBackend::supports_bracketed_paste () const noexcept
{
#ifdef EMACS_USE_HAIKU
  return initialized_;
#else
  return false;
#endif
}

std::pair<int, int>
HaikuBackend::get_terminal_size () const noexcept
{
#ifdef EMACS_USE_HAIKU
  if (!window_ || !initialized_)
    {
      return { 0, 0 };
    }

  BRect frame = window_->Frame ();
  return { static_cast<int> (frame.IntegerHeight ()),
	   static_cast<int> (frame.IntegerWidth ()) };
#else
  return { 0, 0 };
#endif
}

InputEvent
HaikuBackend::read_input () noexcept
{
  InputEvent event;
  event.type = InputEventType::None;

#ifdef EMACS_USE_HAIKU
  // TODO: Implement Haiku event reading from BWindow
  (void) event;
#endif

  return event;
}

void
HaikuBackend::set_raw_mode (bool raw) noexcept
{
  (void) raw;
}

void
HaikuBackend::flush () noexcept
{
#ifdef EMACS_USE_HAIKU
  if (content_view_ && initialized_)
    {
      content_view_->Sync ();
    }
#endif
}

} // namespace emacs
