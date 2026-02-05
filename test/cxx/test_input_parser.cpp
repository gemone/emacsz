// test/cxx/test_input_parser.cpp
// Unit tests for InputParser

#include <cassert>
#include <iostream>
#include "../../src/input_parser.hpp"

using namespace emacs::tui;

void
test_basic_ascii ()
{
  InputParser parser;

  parser.feed ("a");
  auto event = parser.next_event ();
  assert (event.has_value ());
  assert (event->type == InputEventType::Key);
  assert (event->key.unicode == 'a');
  assert (!parser.has_events ());

  std::cout << "test_basic_ascii passed\n";
}

void
test_escape_key ()
{
  InputParser parser;

  parser.feed ("\x1b");
  parser.feed ("a");

  auto esc = parser.next_event ();
  assert (esc.has_value ());
  assert (esc->type == InputEventType::Key);
  assert (esc->key.key == KeyCode::Escape);

  auto a = parser.next_event ();
  assert (a.has_value ());
  assert (a->key.unicode == 'a');

  std::cout << "test_escape_key passed\n";
}

void
test_arrow_keys ()
{
  InputParser parser;

  parser.feed ("\x1b[A");
  auto up = parser.next_event ();
  assert (up.has_value ());
  assert (up->type == InputEventType::Key);
  assert (up->key.key == KeyCode::ArrowUp);

  parser.feed ("\x1b[B");
  auto down = parser.next_event ();
  assert (down.has_value ());
  assert (down->key.key == KeyCode::ArrowDown);

  parser.feed ("\x1b[C");
  auto right = parser.next_event ();
  assert (right.has_value ());
  assert (right->key.key == KeyCode::ArrowRight);

  parser.feed ("\x1b[D");
  auto left = parser.next_event ();
  assert (left.has_value ());
  assert (left->key.key == KeyCode::ArrowLeft);

  std::cout << "test_arrow_keys passed\n";
}

void
test_function_keys ()
{
  InputParser parser;

  parser.feed ("\x1bOP");
  auto f1 = parser.next_event ();
  assert (f1.has_value ());
  assert (f1->type == InputEventType::Key);
  assert (f1->key.key == KeyCode::F1);

  parser.feed ("\x1bOQ");
  auto f2 = parser.next_event ();
  assert (f2.has_value ());
  assert (f2->key.key == KeyCode::F2);

  parser.feed ("\x1b[15~");
  auto f5 = parser.next_event ();
  assert (f5.has_value ());
  assert (f5->key.key == KeyCode::F5);

  std::cout << "test_function_keys passed\n";
}

void
test_special_keys ()
{
  InputParser parser;

  parser.feed ("\x1b[H");
  auto home = parser.next_event ();
  assert (home.has_value ());
  assert (home->key.key == KeyCode::Home);

  parser.feed ("\x1b[F");
  auto end = parser.next_event ();
  assert (end.has_value ());
  assert (end->key.key == KeyCode::End);

  parser.feed ("\x1b[2~");
  auto insert = parser.next_event ();
  assert (insert.has_value ());
  assert (insert->key.key == KeyCode::Insert);

  parser.feed ("\x1b[3~");
  auto del = parser.next_event ();
  assert (del.has_value ());
  assert (del->key.key == KeyCode::Delete);

  std::cout << "test_special_keys passed\n";
}

void
test_ctrl_keys ()
{
  InputParser parser;

  parser.feed ("\x01");
  auto ctrl_a = parser.next_event ();
  assert (ctrl_a.has_value ());
  assert (ctrl_a->type == InputEventType::Key);
  assert (has_modifier (ctrl_a->key.modifiers, KeyModifier::Ctrl));
  assert (ctrl_a->key.unicode == 'a');

  parser.feed ("\x03");
  auto ctrl_c = parser.next_event ();
  assert (ctrl_c.has_value ());
  assert (has_modifier (ctrl_c->key.modifiers, KeyModifier::Ctrl));
  assert (ctrl_c->key.unicode == 'c');

  std::cout << "test_ctrl_keys passed\n";
}

void
test_utf8 ()
{
  InputParser parser;

  parser.feed ("中");
  auto event = parser.next_event ();
  assert (event.has_value ());
  assert (event->type == InputEventType::Key);
  assert (event->key.unicode == 0x4E2D);

  std::cout << "test_utf8 passed\n";
}

void
test_multiple_events ()
{
  InputParser parser;

  parser.feed ("abc\x1b[A");

  auto e1 = parser.next_event ();
  assert (e1.has_value ());
  assert (e1->key.unicode == 'a');

  auto e2 = parser.next_event ();
  assert (e2.has_value ());
  assert (e2->key.unicode == 'b');

  auto e3 = parser.next_event ();
  assert (e3.has_value ());
  assert (e3->key.unicode == 'c');

  auto e4 = parser.next_event ();
  assert (e4.has_value ());
  assert (e4->key.key == KeyCode::ArrowUp);

  assert (!parser.has_events ());

  std::cout << "test_multiple_events passed\n";
}

void
test_partial_sequence ()
{
  InputParser parser;

  parser.feed ("\x1b");
  assert (!parser.has_events ());

  parser.feed ("[");
  assert (!parser.has_events ());

  parser.feed ("A");
  auto event = parser.next_event ();
  assert (event.has_value ());
  assert (event->key.key == KeyCode::ArrowUp);

  std::cout << "test_partial_sequence passed\n";
}

int
main ()
{
  test_basic_ascii ();
  test_escape_key ();
  test_arrow_keys ();
  test_function_keys ();
  test_special_keys ();
  test_ctrl_keys ();
  test_utf8 ();
  test_multiple_events ();
  test_partial_sequence ();

  std::cout << "\nAll InputParser tests passed!\n";
  return 0;
}
