// test/cxx/test_command_registry.cpp
// Unit tests for command registry

#include <cassert>
#include <cstdio>
#include <cstdlib>

#include "../../src/emacs_command_registry.hpp"

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
test_registry_singleton ()
{
  CommandRegistry &a = CommandRegistry::instance ();
  CommandRegistry &b = CommandRegistry::instance ();
  assert (&a == &b);

  std::printf ("test_registry_singleton passed\n");
}

static void
test_register_command ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  bool ran = false;
  registry.register_command (
    "self-insert", [&ran] (CommandContext &) { ran = true; },
    "insert", "i", 0, 0);

  const CommandDef *def = registry.lookup ("self-insert");
  assert (def);
  assert (def->name == "self-insert");
  assert (def->docstring == "insert");
  assert (def->interactive.is_interactive ());
  assert (def->min_args == 0);
  assert (def->max_args == 0);

  CommandContext ctx;
  ctx.buffer = nullptr;
  ctx.prefix_argument = 0;
  ctx.has_prefix = false;
  ctx.raw_prefix = false;
  assert (registry.execute ("self-insert", ctx));
  assert (ran);

  std::printf ("test_register_command passed\n");
}

static void
test_lookup_nonexistent ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  const CommandDef *def = registry.lookup ("missing");
  assert (!def);

  std::printf ("test_lookup_nonexistent passed\n");
}

static void
test_has_command ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  registry.register_command (
    "forward-char", [] (CommandContext &) {}, "", "i", 0, 0);
  assert (registry.has_command ("forward-char"));
  assert (!registry.has_command ("backward-char"));

  std::printf ("test_has_command passed\n");
}

static void
test_execute_command ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  int counter = 0;
  registry.register_command (
    "increment", [&counter] (CommandContext &ctx)
      { counter += ctx.prefix_argument; }, "", "", 0, 0);

  CommandContext ctx;
  ctx.buffer = nullptr;
  ctx.prefix_argument = 3;
  ctx.has_prefix = true;
  ctx.raw_prefix = false;
  bool ok = registry.execute ("increment", ctx);
  assert (ok);
  assert (counter == 3);

  std::printf ("test_execute_command passed\n");
}

static void
test_execute_nonexistent ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  CommandContext ctx;
  ctx.buffer = nullptr;
  ctx.prefix_argument = 0;
  ctx.has_prefix = false;
  ctx.raw_prefix = false;
  assert (!registry.execute ("nope", ctx));

  std::printf ("test_execute_nonexistent passed\n");
}

static void
test_list_commands ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  registry.register_command (
    "beta", [] (CommandContext &) {}, "", "", 0, 0);
  registry.register_command (
    "alpha", [] (CommandContext &) {}, "", "", 0, 0);

  gc_vector_t<const CommandDef *> list = registry.list_commands ();
  assert (list.size () == 2);
  assert (list[0]->name == "alpha");
  assert (list[1]->name == "beta");

  std::printf ("test_list_commands passed\n");
}

static void
test_list_interactive ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  registry.register_command (
    "non-interactive", [] (CommandContext &) {}, "", "", 0, 0);
  registry.register_command (
    "interactive", [] (CommandContext &) {}, "", "i", 0, 0);

  gc_vector_t<const CommandDef *> list
    = registry.list_interactive_commands ();
  assert (list.size () == 1);
  assert (list[0]->name == "interactive");

  std::printf ("test_list_interactive passed\n");
}

static void
test_complete_prefix ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  registry.register_command (
    "forward-char", [] (CommandContext &) {}, "", "", 0, 0);
  registry.register_command (
    "forward-word", [] (CommandContext &) {}, "", "", 0, 0);
  registry.register_command (
    "backward-char", [] (CommandContext &) {}, "", "", 0, 0);

  gc_vector_t<const CommandDef *> list
    = registry.complete_prefix ("for");
  assert (list.size () == 2);
  assert (list[0]->name == "forward-char");
  assert (list[1]->name == "forward-word");

  std::printf ("test_complete_prefix passed\n");
}

static void
test_count ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  registry
    .register_command ("one", [] (CommandContext &) {}, "", "", 0, 0);
  registry
    .register_command ("two", [] (CommandContext &) {}, "", "", 0, 0);

  assert (registry.count () == 2);

  std::printf ("test_count passed\n");
}

static void
test_clear ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  registry
    .register_command ("one", [] (CommandContext &) {}, "", "", 0, 0);
  registry
    .register_command ("two", [] (CommandContext &) {}, "", "", 0, 0);
  registry.clear ();

  assert (registry.count () == 0);
  assert (!registry.has_command ("one"));

  std::printf ("test_clear passed\n");
}

static void
test_overwrite ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  int value = 0;
  registry.register_command (
    "dup", [&value] (CommandContext &) { value = 1; }, "", "", 0, 0);
  registry.register_command (
    "dup", [&value] (CommandContext &) { value = 2; }, "", "", 0, 0);

  CommandContext ctx;
  ctx.buffer = nullptr;
  ctx.prefix_argument = 0;
  ctx.has_prefix = false;
  ctx.raw_prefix = false;
  bool ok = registry.execute ("dup", ctx);
  assert (ok);
  assert (value == 2);

  std::printf ("test_overwrite passed\n");
}

static void
test_command_context ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  CommandContext seen;
  seen.buffer = nullptr;
  seen.prefix_argument = 0;
  seen.has_prefix = false;
  seen.raw_prefix = false;

  registry.register_command (
    "ctx", [&seen] (CommandContext &ctx) { seen = ctx; }, "", "", 0,
    0);

  CommandContext ctx;
  int buffer_marker = 42;
  ctx.buffer = reinterpret_cast<EmacsBuffer *> (&buffer_marker);
  ctx.prefix_argument = 7;
  ctx.has_prefix = true;
  ctx.raw_prefix = true;
  bool ok = registry.execute ("ctx", ctx);
  assert (ok);

  assert (seen.buffer == ctx.buffer);
  assert (seen.prefix_argument == 7);
  assert (seen.has_prefix);
  assert (seen.raw_prefix);

  std::printf ("test_command_context passed\n");
}

static void
test_extern_c_register ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  int called = 0;
  auto stub = [] (void *ptr)
    {
      int *val = static_cast<int *> (ptr);
      if (val)
	*val = 9;
    };

  int result = emacs_cxx_register_command ("c-command", stub, "doc");
  assert (result == 0);
  assert (registry.has_command ("c-command"));

  int buffer = 0;
  CommandContext ctx;
  ctx.buffer = reinterpret_cast<EmacsBuffer *> (&buffer);
  ctx.prefix_argument = 0;
  ctx.has_prefix = false;
  ctx.raw_prefix = false;
  bool ok = registry.execute ("c-command", ctx);
  assert (ok);
  assert (buffer == 9);

  assert (!called);

  std::printf ("test_extern_c_register passed\n");
}

static void
test_extern_c_execute ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  int value = 0;
  auto stub = [] (void *ptr)
    {
      int *val = static_cast<int *> (ptr);
      if (val)
	*val = 5;
    };

  int reg_result = emacs_cxx_register_command ("exec", stub, "doc");
  assert (reg_result == 0);

  int buffer = 0;
  int exec_result = emacs_cxx_execute_command ("exec", &buffer);
  assert (exec_result == 0);
  assert (buffer == 5);

  std::printf ("test_extern_c_execute passed\n");
}

static void
test_extern_c_has ()
{
  CommandRegistry &registry = CommandRegistry::instance ();
  registry.clear ();

  auto stub = [] (void *) {};
  int result = emacs_cxx_register_command ("has-test", stub, "doc");
  assert (result == 0);
  assert (emacs_cxx_has_command ("has-test") == 1);
  assert (emacs_cxx_has_command ("missing") == 0);

  std::printf ("test_extern_c_has passed\n");
}

int
main ()
{
  std::printf ("Running command registry tests...\n\n");

  test_registry_singleton ();
  test_register_command ();
  test_lookup_nonexistent ();
  test_has_command ();
  test_execute_command ();
  test_execute_nonexistent ();
  test_list_commands ();
  test_list_interactive ();
  test_complete_prefix ();
  test_count ();
  test_clear ();
  test_overwrite ();
  test_command_context ();
  test_extern_c_register ();
  test_extern_c_execute ();
  test_extern_c_has ();

  std::printf ("\n✅ All command registry tests passed!\n");
  return 0;
}
