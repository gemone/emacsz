// test/cxx/test_emacs_undo.cpp
// Unit tests for Emacs undo/redo manager

#include <cassert>
#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_undo.hpp"

using namespace emacs;

extern "C"
{
  void *lisp_malloc (size_t size) { return std::malloc (size); }
  void lisp_free (void *ptr) { std::free (ptr); }
  void *lisp_realloc (void *ptr, size_t size)
  {
    return std::realloc (ptr, size);
  }
}

static void
check_record (const UndoRecord &record, UndoRecordType type,
	      ptrdiff_t pos, const char *text, ptrdiff_t old_point)
{
  assert (record.type == type);
  assert (record.position == pos);
  assert (record.text == text);
  assert (record.old_point == old_point);
}

static void
test_create ()
{
  UndoManager manager;

  assert (!manager.can_undo ());
  assert (!manager.can_redo ());
  assert (manager.undo_count () == 0);
  assert (manager.redo_count () == 0);
  assert (!manager.is_recording ());
  assert (manager.is_enabled ());

  std::printf ("test_create passed\n");
}

static void
test_record_insert ()
{
  UndoManager manager;

  manager.record_insert (3, "abc", 2);

  assert (manager.can_undo ());
  assert (manager.undo_count () == 1);

  std::printf ("test_record_insert passed\n");
}

static void
test_record_delete ()
{
  UndoManager manager;

  manager.record_delete (2, "xy", 4);

  assert (manager.can_undo ());
  assert (manager.undo_count () == 1);

  std::printf ("test_record_delete passed\n");
}

static void
test_undo_insert ()
{
  UndoManager manager;

  manager.record_insert (4, "xyz", 2);
  const UndoGroup &group = manager.prepare_undo ();

  assert (group.records.size () == 1);
  check_record (group.records[0], UndoRecordType::INSERT, 4, "xyz",
		2);

  std::printf ("test_undo_insert passed\n");
}

static void
test_undo_delete ()
{
  UndoManager manager;

  manager.record_delete (6, "ZZ", 5);
  const UndoGroup &group = manager.prepare_undo ();

  assert (group.records.size () == 1);
  check_record (group.records[0], UndoRecordType::DELETE, 6, "ZZ", 5);

  std::printf ("test_undo_delete passed\n");
}

static void
test_redo_after_undo ()
{
  UndoManager manager;

  manager.record_insert (1, "a", 1);
  const UndoGroup &undo_group = manager.prepare_undo ();
  assert (undo_group.records.size () == 1);
  manager.commit_undo ();

  assert (!manager.can_undo ());
  assert (manager.can_redo ());

  const UndoGroup &redo_group = manager.prepare_redo ();
  assert (redo_group.records.size () == 1);
  check_record (redo_group.records[0], UndoRecordType::INSERT, 1, "a",
		1);
  manager.commit_redo ();

  assert (manager.can_undo ());
  assert (!manager.can_redo ());

  std::printf ("test_redo_after_undo passed\n");
}

static void
test_redo_cleared_on_edit ()
{
  UndoManager manager;

  manager.record_insert (1, "a", 1);
  const UndoGroup &undo_group = manager.prepare_undo ();
  assert (undo_group.records.size () == 1);
  manager.commit_undo ();

  assert (manager.can_redo ());

  manager.record_delete (1, "a", 1);

  assert (!manager.can_redo ());
  assert (manager.redo_count () == 0);

  std::printf ("test_redo_cleared_on_edit passed\n");
}

static void
test_group_multiple_records ()
{
  UndoManager manager;

  manager.begin_group ();
  manager.record_insert (1, "a", 1);
  manager.record_delete (2, "b", 2);
  manager.record_insert (3, "c", 3);
  manager.end_group ();

  assert (manager.undo_count () == 1);
  const UndoGroup &group = manager.prepare_undo ();
  assert (group.records.size () == 3);

  std::printf ("test_group_multiple_records passed\n");
}

static void
test_undo_group_reverse_order ()
{
  UndoManager manager;

  manager.begin_group ();
  manager.record_insert (1, "a", 1);
  manager.record_delete (2, "b", 2);
  manager.record_insert (3, "c", 3);
  manager.end_group ();

  const UndoGroup &group = manager.prepare_undo ();
  assert (group.records.size () == 3);

  check_record (group.records[0], UndoRecordType::INSERT, 3, "c", 3);
  check_record (group.records[1], UndoRecordType::DELETE, 2, "b", 2);
  check_record (group.records[2], UndoRecordType::INSERT, 1, "a", 1);

  std::printf ("test_undo_group_reverse_order passed\n");
}

static void
test_multiple_groups ()
{
  UndoManager manager;

  manager.record_insert (1, "a", 1);
  manager.record_delete (2, "b", 2);
  manager.record_insert (3, "c", 3);

  assert (manager.undo_count () == 3);

  const UndoGroup &group1 = manager.prepare_undo ();
  check_record (group1.records[0], UndoRecordType::INSERT, 3, "c", 3);
  manager.commit_undo ();

  const UndoGroup &group2 = manager.prepare_undo ();
  check_record (group2.records[0], UndoRecordType::DELETE, 2, "b", 2);
  manager.commit_undo ();

  const UndoGroup &group3 = manager.prepare_undo ();
  check_record (group3.records[0], UndoRecordType::INSERT, 1, "a", 1);
  manager.commit_undo ();

  assert (!manager.can_undo ());

  std::printf ("test_multiple_groups passed\n");
}

static void
test_max_undo_count ()
{
  UndoManager manager;

  manager.set_max_undo_count (2);
  manager.record_insert (1, "a", 1);
  manager.record_insert (2, "b", 2);
  manager.record_insert (3, "c", 3);

  assert (manager.undo_count () == 2);

  const UndoGroup &group1 = manager.prepare_undo ();
  check_record (group1.records[0], UndoRecordType::INSERT, 3, "c", 3);
  manager.commit_undo ();

  const UndoGroup &group2 = manager.prepare_undo ();
  check_record (group2.records[0], UndoRecordType::INSERT, 2, "b", 2);
  manager.commit_undo ();

  assert (!manager.can_undo ());

  std::printf ("test_max_undo_count passed\n");
}

static void
test_disabled_recording ()
{
  UndoManager manager;

  manager.set_enabled (false);
  manager.record_insert (1, "a", 1);
  manager.begin_group ();
  manager.record_delete (1, "a", 1);
  manager.end_group ();

  assert (!manager.can_undo ());
  assert (manager.undo_count () == 0);

  manager.set_enabled (true);
  manager.record_insert (1, "a", 1);
  assert (manager.can_undo ());

  std::printf ("test_disabled_recording passed\n");
}

static void
test_clear ()
{
  UndoManager manager;

  manager.record_insert (1, "a", 1);
  manager.record_delete (2, "b", 2);

  manager.clear ();

  assert (!manager.can_undo ());
  assert (!manager.can_redo ());
  assert (manager.undo_count () == 0);
  assert (manager.redo_count () == 0);

  std::printf ("test_clear passed\n");
}

static void
test_empty_group_not_pushed ()
{
  UndoManager manager;

  manager.begin_group ();
  manager.end_group ();

  assert (!manager.can_undo ());
  assert (manager.undo_count () == 0);

  std::printf ("test_empty_group_not_pushed passed\n");
}

static void
test_nested_undo_redo ()
{
  UndoManager manager;

  manager.record_insert (1, "a", 1);
  manager.record_insert (2, "b", 2);
  manager.record_insert (3, "c", 3);

  const UndoGroup &undo_group1 = manager.prepare_undo ();
  assert (undo_group1.records.size () == 1);
  manager.commit_undo ();
  const UndoGroup &undo_group2 = manager.prepare_undo ();
  assert (undo_group2.records.size () == 1);
  manager.commit_undo ();

  assert (manager.undo_count () == 1);
  assert (manager.redo_count () == 2);

  const UndoGroup &redo_group = manager.prepare_redo ();
  assert (redo_group.records.size () == 1);
  manager.commit_redo ();

  assert (manager.undo_count () == 2);
  assert (manager.redo_count () == 1);

  const UndoGroup &undo_group3 = manager.prepare_undo ();
  assert (undo_group3.records.size () == 1);
  manager.commit_undo ();

  assert (manager.undo_count () == 1);
  assert (manager.redo_count () == 2);

  std::printf ("test_nested_undo_redo passed\n");
}

static void
test_redo_forward_order ()
{
  UndoManager manager;

  manager.begin_group ();
  manager.record_insert (1, "a", 1);
  manager.record_delete (2, "b", 2);
  manager.end_group ();

  const UndoGroup &undo_group = manager.prepare_undo ();
  assert (undo_group.records.size () == 2);
  manager.commit_undo ();

  const UndoGroup &redo_group = manager.prepare_redo ();
  assert (redo_group.records.size () == 2);

  check_record (redo_group.records[0], UndoRecordType::INSERT, 1, "a",
		1);
  check_record (redo_group.records[1], UndoRecordType::DELETE, 2, "b",
		2);

  std::printf ("test_redo_forward_order passed\n");
}

int
main ()
{
  std::printf ("Running Emacs undo tests...\n\n");

  test_create ();
  test_record_insert ();
  test_record_delete ();
  test_undo_insert ();
  test_undo_delete ();
  test_redo_after_undo ();
  test_redo_cleared_on_edit ();
  test_group_multiple_records ();
  test_undo_group_reverse_order ();
  test_multiple_groups ();
  test_max_undo_count ();
  test_disabled_recording ();
  test_clear ();
  test_empty_group_not_pushed ();
  test_nested_undo_redo ();
  test_redo_forward_order ();

  std::printf ("\n✅ All Emacs undo tests passed!\n");
  return 0;
}
