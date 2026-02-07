// test/cxx/test_sdl2_backend.cpp
// SDL2 backend mock tests (headless)

#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "../../src/containers.hpp"

namespace emacs
{

struct TerminalColor
{
  uint8_t red;
  uint8_t green;
  uint8_t blue;
};

struct TerminalGlyph
{
  char32_t codepoint;
  uint32_t face_id;
  TerminalColor background;
  TerminalColor foreground;
  bool wide;
  bool padding;
  bool bold;
  bool italic;
  bool underline;
  bool inverse;
  bool blink;
};

struct CursorPosition
{
  int row;
  int col;
};

enum class InputEventType
{
  None,
  Key,
  Mouse,
  Resize,
  Error
};

enum class MouseButton
{
  None,
  Left,
  Right,
  Middle,
  WheelUp,
  WheelDown,
  Release
};

struct InputEvent
{
  InputEventType type = InputEventType::None;
  uint32_t key = 0;
  uint32_t ch = 0;
  uint8_t mod = 0;
  MouseButton button = MouseButton::None;
  int x = 0;
  int y = 0;
  int w = 0;
  int h = 0;
};

template <typename T> class Span
{
private:
  T *data_;
  size_t size_;

public:
  Span (T *data, size_t size) : data_ (data), size_ (size) {}

  T *begin () const { return data_; }
  T *end () const { return data_ + size_; }
  [[nodiscard]] size_t size () const { return size_; }
  T &operator[] (size_t index) const { return data_[index]; }
};

template <typename T> constexpr bool TerminalBackend = true;

} // namespace emacs

using namespace emacs;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void *lisp_malloc_unsafe (size_t size)
  {
    return std::malloc (size);
  }
  void lisp_free (void *ptr) { std::free (ptr); }
  void *lisp_malloc_uncleared (size_t size)
  {
    return std::malloc (size);
  }
  void *lisp_realloc (void *ptr, size_t size)
  {
    return std::realloc (ptr, size);
  }
}

namespace
{

struct Cell
{
  TerminalGlyph glyph{};
  bool empty = true;
};

class MockGraphicalBackend
{
private:
  bool initialized_ = false;
  int rows_ = 5;
  int cols_ = 10;
  CursorPosition cursor_{ 0, 0 };
  bool raw_mode_ = false;
  gc_vector_t<Cell> cells_;

  size_t index (int row, int col) const noexcept
  {
    return static_cast<size_t> (row * cols_ + col);
  }

public:
  MockGraphicalBackend ()
      : cells_ (static_cast<size_t> (rows_ * cols_))
  {
  }

  [[nodiscard]] bool init ()
  {
    initialized_ = true;
    return true;
  }

  void cleanup () { initialized_ = false; }

  void write_glyphs (Span<TerminalGlyph> glyphs)
  {
    for (const auto &glyph : glyphs)
      {
	if (cursor_.row >= rows_ || cursor_.col >= cols_)
	  return;
	Cell &cell = cells_[index (cursor_.row, cursor_.col)];
	cell.glyph = glyph;
	cell.empty = false;
	cursor_.col++;
      }
  }

  void write_text (std::string_view text)
  {
    for (unsigned char ch : text)
      {
	TerminalGlyph glyph{};
	glyph.codepoint = ch;
	write_glyphs (Span<TerminalGlyph> (&glyph, 1));
      }
  }

  void clear_to_end (CursorPosition pos)
  {
    for (int row = pos.row; row < rows_; ++row)
      {
	int start = (row == pos.row) ? pos.col : 0;
	for (int col = start; col < cols_; ++col)
	  cells_[index (row, col)].empty = true;
      }
  }

  void clear_frame ()
  {
    for (auto &cell : cells_)
      cell.empty = true;
  }

  void clear_end_of_line (CursorPosition pos)
  {
    for (int col = pos.col; col < cols_; ++col)
      cells_[index (pos.row, col)].empty = true;
  }

  void set_cursor_position (CursorPosition pos) { cursor_ = pos; }

  [[nodiscard]] CursorPosition get_cursor_position () const
  {
    return cursor_;
  }

  void insert_glyphs (CursorPosition pos, Span<TerminalGlyph> glyphs)
  {
    for (int col = cols_ - 1;
	 col >= pos.col + static_cast<int> (glyphs.size ()); --col)
      {
	cells_[index (pos.row, col)]
	  = cells_[index (pos.row,
			  col - static_cast<int> (glyphs.size ()))];
      }

    for (size_t i = 0; i < glyphs.size (); ++i)
      {
	Cell &cell
	  = cells_[index (pos.row, pos.col + static_cast<int> (i))];
	cell.glyph = glyphs[i];
	cell.empty = false;
      }
  }

  void delete_glyphs (CursorPosition pos, std::size_t n)
  {
    for (int col = pos.col; col < cols_ - static_cast<int> (n); ++col)
      {
	cells_[index (pos.row, col)]
	  = cells_[index (pos.row, col + static_cast<int> (n))];
      }
    for (int col = cols_ - static_cast<int> (n); col < cols_; ++col)
      cells_[index (pos.row, col)].empty = true;
  }

  void insert_lines (CursorPosition pos, std::size_t n)
  {
    for (int row = rows_ - 1; row >= pos.row + static_cast<int> (n);
	 --row)
      {
	for (int col = 0; col < cols_; ++col)
	  cells_[index (row, col)]
	    = cells_[index (row - static_cast<int> (n), col)];
      }
    for (int row = pos.row; row < pos.row + static_cast<int> (n);
	 ++row)
      {
	for (int col = 0; col < cols_; ++col)
	  cells_[index (row, col)].empty = true;
      }
  }

  void delete_lines (CursorPosition pos, std::size_t n)
  {
    for (int row = pos.row; row < rows_ - static_cast<int> (n); ++row)
      {
	for (int col = 0; col < cols_; ++col)
	  cells_[index (row, col)]
	    = cells_[index (row + static_cast<int> (n), col)];
      }
    for (int row = rows_ - static_cast<int> (n); row < rows_; ++row)
      {
	for (int col = 0; col < cols_; ++col)
	  cells_[index (row, col)].empty = true;
      }
  }

  [[nodiscard]] bool supports_colors () const { return true; }
  [[nodiscard]] bool supports_truecolor () const { return true; }
  [[nodiscard]] bool supports_blinking_cursor () const
  {
    return true;
  }
  [[nodiscard]] bool supports_bracketed_paste () const
  {
    return true;
  }

  [[nodiscard]] std::pair<int, int> get_terminal_size () const
  {
    return { rows_, cols_ };
  }

  [[nodiscard]] InputEvent read_input () { return InputEvent{}; }
  void set_raw_mode (bool raw) { raw_mode_ = raw; }
  void flush () {}

  [[nodiscard]] bool cell_empty (int row, int col) const
  {
    return cells_[index (row, col)].empty;
  }

  [[nodiscard]] char32_t cell_codepoint (int row, int col) const
  {
    return cells_[index (row, col)].glyph.codepoint;
  }

  [[nodiscard]] bool raw_mode () const { return raw_mode_; }
};

#if EMACS_HAS_CONCEPTS
static_assert (TerminalBackend<MockGraphicalBackend>);
#else
static_assert (true);
#endif

} // namespace

static void
test_mock_init ()
{
  MockGraphicalBackend backend;
  assert (backend.init ());
  std::printf ("test_mock_init passed\n");
}

static void
test_terminal_size ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  auto size = backend.get_terminal_size ();
  assert (size.first == 5);
  assert (size.second == 10);
  std::printf ("test_terminal_size passed\n");
}

static void
test_cursor_roundtrip ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.set_cursor_position ({ 2, 3 });
  CursorPosition pos = backend.get_cursor_position ();
  assert (pos.row == 2);
  assert (pos.col == 3);
  std::printf ("test_cursor_roundtrip passed\n");
}

static void
test_write_glyphs ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  TerminalGlyph glyph{};
  glyph.codepoint = 'A';
  backend.write_glyphs (Span<TerminalGlyph> (&glyph, 1));
  assert (!backend.cell_empty (0, 0));
  assert (backend.cell_codepoint (0, 0) == 'A');
  std::printf ("test_write_glyphs passed\n");
}

static void
test_write_text_advances_cursor ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.write_text ("ABC");
  CursorPosition pos = backend.get_cursor_position ();
  assert (pos.col == 3);
  std::printf ("test_write_text_advances_cursor passed\n");
}

static void
test_clear_frame ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.write_text ("AB");
  backend.clear_frame ();
  assert (backend.cell_empty (0, 0));
  assert (backend.cell_empty (0, 1));
  std::printf ("test_clear_frame passed\n");
}

static void
test_clear_end_of_line ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.write_text ("ABCDE");
  backend.clear_end_of_line ({ 0, 2 });
  assert (!backend.cell_empty (0, 0));
  assert (backend.cell_empty (0, 2));
  assert (backend.cell_empty (0, 4));
  std::printf ("test_clear_end_of_line passed\n");
}

static void
test_clear_to_end ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.write_text ("ABCDE");
  backend.set_cursor_position ({ 1, 0 });
  backend.write_text ("12345");
  backend.clear_to_end ({ 0, 3 });
  assert (!backend.cell_empty (0, 2));
  assert (backend.cell_empty (0, 3));
  assert (backend.cell_empty (1, 0));
  std::printf ("test_clear_to_end passed\n");
}

static void
test_supports_colors ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  assert (backend.supports_colors ());
  assert (backend.supports_truecolor ());
  assert (backend.supports_blinking_cursor ());
  assert (backend.supports_bracketed_paste ());
  std::printf ("test_supports_colors passed\n");
}

static void
test_insert_glyphs_shifts_right ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.write_text ("ABCDE");
  TerminalGlyph glyph{};
  glyph.codepoint = 'Z';
  backend.insert_glyphs ({ 0, 1 }, Span<TerminalGlyph> (&glyph, 1));
  assert (backend.cell_codepoint (0, 1) == 'Z');
  assert (backend.cell_codepoint (0, 2) == 'B');
  std::printf ("test_insert_glyphs_shifts_right passed\n");
}

static void
test_delete_glyphs_shifts_left ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.write_text ("ABCDE");
  backend.delete_glyphs ({ 0, 1 }, 2);
  assert (backend.cell_codepoint (0, 1) == 'D');
  std::printf ("test_delete_glyphs_shifts_left passed\n");
}

static void
test_insert_lines_shifts_down ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.write_text ("AB");
  backend.set_cursor_position ({ 1, 0 });
  backend.write_text ("CD");
  backend.insert_lines ({ 0, 0 }, 1);
  assert (backend.cell_empty (0, 0));
  assert (backend.cell_codepoint (1, 0) == 'A');
  std::printf ("test_insert_lines_shifts_down passed\n");
}

static void
test_delete_lines_shifts_up ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.write_text ("AB");
  backend.set_cursor_position ({ 1, 0 });
  backend.write_text ("CD");
  backend.delete_lines ({ 0, 0 }, 1);
  assert (backend.cell_codepoint (0, 0) == 'C');
  std::printf ("test_delete_lines_shifts_up passed\n");
}

static void
test_raw_mode_flag ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.set_raw_mode (true);
  assert (backend.raw_mode ());
  std::printf ("test_raw_mode_flag passed\n");
}

static void
test_flush_callable ()
{
  MockGraphicalBackend backend;
  (void) backend.init ();
  backend.flush ();
  std::printf ("test_flush_callable passed\n");
}

int
main ()
{
  test_mock_init ();
  test_terminal_size ();
  test_cursor_roundtrip ();
  test_write_glyphs ();
  test_write_text_advances_cursor ();
  test_clear_frame ();
  test_clear_end_of_line ();
  test_clear_to_end ();
  test_supports_colors ();
  test_insert_glyphs_shifts_right ();
  test_delete_glyphs_shifts_left ();
  test_insert_lines_shifts_down ();
  test_delete_lines_shifts_up ();
  test_raw_mode_flag ();
  test_flush_callable ();
  return 0;
}
