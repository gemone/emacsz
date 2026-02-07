// src/androidterm.cpp
#include "androidterm.hpp"

namespace emacs
{

AndroidBackend::AndroidBackend () noexcept
#ifdef EMACS_USE_ANDROID
    : window_ (nullptr), input_queue_ (nullptr), initialized_ (false),
      cursor_{ 0, 0 }
#else
    : initialized_ (false)
#endif
{
}

AndroidBackend::~AndroidBackend () { cleanup (); }

bool
AndroidBackend::init () noexcept
{
#ifdef EMACS_USE_ANDROID
  // TODO: Initialize ANativeWindow and AInputQueue
  // from Android activity/app context

  initialized_ = false;
  return false;
#else
  return false;
#endif
}

void
AndroidBackend::cleanup () noexcept
{
#ifdef EMACS_USE_ANDROID
  if (window_)
    {
      ANativeWindow_release (window_);
      window_ = nullptr;
    }

  input_queue_ = nullptr;
  initialized_ = false;
#endif
}

void
AndroidBackend::write_glyphs (
  std::span<TerminalGlyph> glyphs) noexcept
{
#ifdef EMACS_USE_ANDROID
  if (!window_ || !initialized_)
    {
      return;
    }

  // TODO: Implement Android native window rendering
  for (const auto &glyph : glyphs)
    {
      (void) glyph;
    }
#else
  (void) glyphs;
#endif
}

void
AndroidBackend::write_text (std::string_view text) noexcept
{
#ifdef EMACS_USE_ANDROID
  if (!window_ || !initialized_)
    {
      return;
    }

  // TODO: Implement Android text rendering
  (void) text;
#else
  (void) text;
#endif
}

void
AndroidBackend::clear_to_end (CursorPosition pos) noexcept
{
  (void) pos;
}

void
AndroidBackend::clear_frame () noexcept
{
#ifdef EMACS_USE_ANDROID
  if (!window_ || !initialized_)
    {
      return;
    }

  ANativeWindow_Buffer buffer;
  if (ANativeWindow_lock (window_, &buffer, nullptr) == 0)
    {
      // Clear buffer to black
      if (buffer.bits)
	{
	  int size = buffer.stride * buffer.height * 4;
	  for (int i = 0; i < size; ++i)
	    {
	      static_cast<uint8_t *> (buffer.bits)[i] = 0;
	    }
	}

      ANativeWindow_unlockAndPost (window_);
    }
#endif
}

void
AndroidBackend::clear_end_of_line (CursorPosition pos) noexcept
{
  (void) pos;
}

void
AndroidBackend::set_cursor_position (CursorPosition pos) noexcept
{
#ifdef EMACS_USE_ANDROID
  cursor_ = pos;
#else
  (void) pos;
#endif
}

CursorPosition
AndroidBackend::get_cursor_position () const noexcept
{
#ifdef EMACS_USE_ANDROID
  return cursor_;
#else
  return { 0, 0 };
#endif
}

void
AndroidBackend::insert_glyphs (
  CursorPosition pos, std::span<TerminalGlyph> glyphs) noexcept
{
  (void) pos;
  (void) glyphs;
}

void
AndroidBackend::delete_glyphs (CursorPosition pos,
			       std::size_t n) noexcept
{
  (void) pos;
  (void) n;
}

void
AndroidBackend::insert_lines (CursorPosition pos,
			      std::size_t n) noexcept
{
  (void) pos;
  (void) n;
}

void
AndroidBackend::delete_lines (CursorPosition pos,
			      std::size_t n) noexcept
{
  (void) pos;
  (void) n;
}

bool
AndroidBackend::supports_colors () const noexcept
{
#ifdef EMACS_USE_ANDROID
  return initialized_;
#else
  return false;
#endif
}

bool
AndroidBackend::supports_truecolor () const noexcept
{
#ifdef EMACS_USE_ANDROID
  return initialized_;
#else
  return false;
#endif
}

bool
AndroidBackend::supports_blinking_cursor () const noexcept
{
#ifdef EMACS_USE_ANDROID
  return initialized_;
#else
  return false;
#endif
}

bool
AndroidBackend::supports_bracketed_paste () const noexcept
{
#ifdef EMACS_USE_ANDROID
  return initialized_;
#else
  return false;
#endif
}

std::pair<int, int>
AndroidBackend::get_terminal_size () const noexcept
{
#ifdef EMACS_USE_ANDROID
  if (!window_ || !initialized_)
    {
      return { 0, 0 };
    }

  int32_t width = ANativeWindow_getWidth (window_);
  int32_t height = ANativeWindow_getHeight (window_);
  return { static_cast<int> (height), static_cast<int> (width) };
#else
  return { 0, 0 };
#endif
}

InputEvent
AndroidBackend::read_input () noexcept
{
  InputEvent event;
  event.type = InputEventType::None;

#ifdef EMACS_USE_ANDROID
  if (!input_queue_ || !initialized_)
    {
      return event;
    }

  // TODO: Implement Android input queue reading
  // using AInputQueue_getEvent() and AInputEvent processing
  (void) event;
#endif

  return event;
}

void
AndroidBackend::set_raw_mode (bool raw) noexcept
{
  (void) raw;
}

void
AndroidBackend::flush () noexcept
{
#ifdef EMACS_USE_ANDROID
  // Android native window has no explicit flush
  // unlockAndPost handles it
#endif
}

} // namespace emacs
