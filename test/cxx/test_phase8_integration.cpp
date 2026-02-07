// test/cxx/test_phase8_integration.cpp
// Phase 8 End-to-End Integration Tests
//
// Tests cross-component interactions between:
//   - MCP Server + Buffer + CommandRegistry
//   - Mode System + Keymap + CommandDispatcher
//   - Buffer Correctness (mark, narrowing, undo)
//   - Full pipeline: mode → keymap → dispatch → buffer
//
// 15 integration tests.

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <string>

extern "C"
{
  void *lisp_malloc (size_t s) { return std::malloc (s); }
  void *lisp_malloc_unsafe (size_t s) { return std::malloc (s); }
  void lisp_free (void *p) { std::free (p); }
  void *lisp_malloc_uncleared (size_t s) { return std::malloc (s); }
  void *lisp_realloc (void *p, size_t s)
  {
    return std::realloc (p, s);
  }
}

#include "../../src/emacs_buffer.hpp"
#include "../../src/emacs_command_registry.hpp"
#include "../../src/emacs_keymap.hpp"
#include "../../src/emacs_mcp_server.hpp"
#include "../../src/emacs_mode.hpp"
#include "../../src/emacs_undo.hpp"
#include "../../src/input_parser.hpp"

using namespace emacs;
using namespace emacs::tui;
using json = nlohmann::json;

static int passed = 0;
static int failed = 0;

#define RUN_TEST(fn)           \
  do                           \
    {                          \
      printf ("  %-55s", #fn); \
      fflush (stdout);         \
      fn ();                   \
      ++passed;                \
      printf ("ok\n");         \
    }                          \
  while (0)

/* ---- Helpers ---- */

static json
parse_response (const std::string &resp)
{
  return json::parse (resp);
}

static std::string
call (McpServer &s, const json &request)
{
  return s.handle_message (request.dump ());
}

static json
tool_call (McpServer &s, int id, const std::string &tool,
	   const json &arguments)
{
  json req;
  req["jsonrpc"] = "2.0";
  req["id"] = id;
  req["method"] = "tools/call";
  req["params"]
    = json{ { "name", tool }, { "arguments", arguments } };
  return parse_response (call (s, req));
}

static std::string
tool_text (const json &resp)
{
  return resp["result"]["content"][0]["text"].get<std::string> ();
}

static void
reset_singletons ()
{
  CommandRegistry::instance ().clear ();
  KeymapManager::instance ().clear ();
  ModeManager::instance ().reset ();
}

// ============================================================
// Test 1: MCP buffer_insert + buffer_state shows modified
// ============================================================
static void
test_mcp_insert_shows_modified ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "m1" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "m1" }, { "text", "abc" } });
  json resp = tool_call (s, 3, "buffer_state", { { "name", "m1" } });
  json state = json::parse (tool_text (resp));
  assert (state["modified"] == true);
  assert (state["size"] == 3);
  assert (state["point"] == 4);
}

// ============================================================
// Test 2: MCP execute_command with custom command
//         modifying buffer via CommandRegistry
// ============================================================
static void
test_mcp_execute_custom_command ()
{
  reset_singletons ();

  static bool command_ran = false;
  command_ran = false;
  CommandRegistry::instance ().register_command (
    "test-phase8-cmd",
    [] (CommandContext &ctx)
      {
	if (ctx.buffer)
	  ctx.buffer->insert_string ("PHASE8");
	command_ran = true;
      },
    "Phase 8 test command", "", 0, 0);

  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "cmd-buf" } });
  tool_call (s, 2, "execute_command",
	     { { "name", "test-phase8-cmd" },
	       { "buffer", "cmd-buf" } });

  assert (command_ran);
  json content
    = tool_call (s, 3, "buffer_content", { { "name", "cmd-buf" } });
  assert (tool_text (content) == "PHASE8");
}

// ============================================================
// Test 3: Mode system defines + activates major mode
//         with keymap binding visible in KeymapManager
// ============================================================
static void
test_mode_keymap_integration ()
{
  reset_singletons ();

  ModeManager &mm = ModeManager::instance ();
  mm.define_major_mode ("test-mode", "Test major mode");

  Keymap &km = mm.mode_keymap ("test-mode");
  km.bind (make_ctrl_keystroke ('t'), "test-mode-special-command");

  EmacsBuffer buffer ("*mode-test*");
  mm.activate_major_mode ("test-mode", &buffer);

  assert (mm.current_major_mode () == "test-mode");

  auto result
    = KeymapManager::instance ().lookup (make_ctrl_keystroke ('t'));
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "test-mode-special-command");
}

// ============================================================
// Test 4: Minor mode keymap overrides major mode
// ============================================================
static void
test_minor_mode_overrides_major ()
{
  reset_singletons ();

  ModeManager &mm = ModeManager::instance ();
  mm.define_major_mode ("base-mode", "Base mode");
  mm.define_minor_mode ("overlay-mode", "Overlay mode");

  Keymap &base_km = mm.mode_keymap ("base-mode");
  base_km.bind (make_ctrl_keystroke ('x'), "base-action");

  Keymap &overlay_km = mm.mode_keymap ("overlay-mode");
  overlay_km.bind (make_ctrl_keystroke ('x'), "overlay-action");

  EmacsBuffer buffer ("*minor*");
  mm.activate_major_mode ("base-mode", &buffer);

  auto r1
    = KeymapManager::instance ().lookup (make_ctrl_keystroke ('x'));
  assert (r1.command_name == "base-action");

  mm.enable_minor_mode ("overlay-mode", &buffer);

  auto r2
    = KeymapManager::instance ().lookup (make_ctrl_keystroke ('x'));
  assert (r2.command_name == "overlay-action");

  mm.disable_minor_mode ("overlay-mode", &buffer);

  auto r3
    = KeymapManager::instance ().lookup (make_ctrl_keystroke ('x'));
  assert (r3.command_name == "base-action");
}

// ============================================================
// Test 5: Buffer mark + region via MCP buffer_state
// ============================================================
static void
test_buffer_mark_via_mcp ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "mrk" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "mrk" }, { "text", "Hello World" } });

  tool_call (s, 3, "cursor_set",
	     { { "name", "mrk" }, { "position", 3 } });

  json resp = tool_call (s, 4, "buffer_state", { { "name", "mrk" } });
  json state = json::parse (tool_text (resp));
  assert (state["point"] == 3);
  assert (state["mark_active"] == false);
}

// ============================================================
// Test 6: Buffer narrowing restricts point_min/point_max
// ============================================================
static void
test_buffer_narrowing ()
{
  EmacsBuffer buffer ("*narrow*", "Hello World!");
  assert (buffer.size () == 12);
  assert (buffer.point_min () == 1);
  assert (buffer.point_max () == 13);

  buffer.narrow_to_region (7, 12);
  assert (buffer.is_narrowed ());
  assert (buffer.point_min () == 7);
  assert (buffer.point_max () == 12);

  buffer.widen ();
  assert (!buffer.is_narrowed ());
  assert (buffer.point_min () == 1);
  assert (buffer.point_max () == 13);
}

// ============================================================
// Test 7: Buffer undo integration — insert + undo
// ============================================================
static void
test_buffer_integrated_undo ()
{
  EmacsBuffer buffer ("*undo-int*");
  buffer.insert_string ("hello");
  assert (buffer.content () == "hello");
  assert (buffer.is_modified ());

  buffer.undo ();
  assert (buffer.content () == "");
}

// ============================================================
// Test 8: Buffer undo + redo round-trip
// ============================================================
static void
test_buffer_undo_redo_roundtrip ()
{
  EmacsBuffer buffer ("*undo-redo*");
  buffer.insert_string ("ABC");
  assert (buffer.content () == "ABC");

  buffer.undo ();
  assert (buffer.content () == "");

  buffer.redo ();
  assert (buffer.content () == "ABC");
}

// ============================================================
// Test 9: Mark + exchange_point_and_mark
// ============================================================
static void
test_mark_exchange ()
{
  EmacsBuffer buffer ("*mark-xchg*", "Hello World");
  buffer.set_point (1);
  buffer.set_mark (6);
  assert (buffer.has_mark ());
  assert (buffer.mark_active ());

  ptrdiff_t old_point = buffer.point ();
  ptrdiff_t old_mark = buffer.mark ();
  buffer.exchange_point_and_mark ();

  assert (buffer.point () == old_mark);
  assert (buffer.mark () == old_point);
}

// ============================================================
// Test 10: MCP buffer_insert + cursor_set + buffer_delete
//          full editing workflow
// ============================================================
static void
test_mcp_full_editing_workflow ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "wf" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "wf" },
	       { "text", "Hello Wonderful World" } });

  tool_call (s, 3, "buffer_delete",
	     { { "name", "wf" }, { "start", 6 }, { "end", 16 } });

  json content
    = tool_call (s, 4, "buffer_content", { { "name", "wf" } });
  assert (tool_text (content) == "Hello World");

  tool_call (s, 5, "buffer_insert",
	     { { "name", "wf" },
	       { "text", " Beautiful" },
	       { "position", 6 } });

  json content2
    = tool_call (s, 6, "buffer_content", { { "name", "wf" } });
  assert (tool_text (content2) == "Hello Beautiful World");
}

// ============================================================
// Test 11: Mode hooks fire on activation
// ============================================================
static void
test_mode_hooks ()
{
  reset_singletons ();

  ModeManager &mm = ModeManager::instance ();
  mm.define_major_mode ("hook-mode", "Mode with hooks");

  static bool hook_fired = false;
  hook_fired = false;
  mm.add_mode_hook ("hook-mode", [] () { hook_fired = true; }, true);

  EmacsBuffer buffer ("*hooks*");
  mm.activate_major_mode ("hook-mode", &buffer);
  assert (hook_fired);
}

// ============================================================
// Test 12: Mode parent keymap inheritance
// ============================================================
static void
test_mode_parent_keymap ()
{
  reset_singletons ();

  ModeManager &mm = ModeManager::instance ();
  mm.define_major_mode ("parent-mode", "Parent mode");
  mm.define_major_mode ("child-mode", "Child mode", "parent-mode");

  Keymap &parent_km = mm.mode_keymap ("parent-mode");
  parent_km.bind (make_ctrl_keystroke ('p'), "parent-command");

  Keymap &child_km = mm.mode_keymap ("child-mode");

  auto result = child_km.lookup (make_ctrl_keystroke ('p'));
  assert (result.type == KeyLookupType::Command);
  assert (result.command_name == "parent-command");

  child_km.bind (make_ctrl_keystroke ('p'), "child-override");
  auto result2 = child_km.lookup (make_ctrl_keystroke ('p'));
  assert (result2.command_name == "child-override");
}

// ============================================================
// Test 13: MCP server + command registry + buffer pipeline
//          Register command → create buffer → execute via MCP
//          → verify buffer state via MCP
// ============================================================
static void
test_mcp_command_buffer_pipeline ()
{
  reset_singletons ();

  CommandRegistry::instance ().register_command (
    "insert-greeting",
    [] (CommandContext &ctx)
      {
	if (ctx.buffer)
	  ctx.buffer->insert_string ("Greetings!");
      },
    "Insert greeting text", "", 0, 0);

  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "pipe" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "pipe" }, { "text", "Start: " } });

  tool_call (s, 3, "execute_command",
	     { { "name", "insert-greeting" }, { "buffer", "pipe" } });

  json content
    = tool_call (s, 4, "buffer_content", { { "name", "pipe" } });
  assert (tool_text (content) == "Start: Greetings!");

  json state
    = tool_call (s, 5, "buffer_state", { { "name", "pipe" } });
  json st = json::parse (tool_text (state));
  assert (st["size"] == 17);
  assert (st["modified"] == true);
}

// ============================================================
// Test 14: Multiple MCP buffers with independent state
// ============================================================
static void
test_mcp_multiple_buffers_independent ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "a" } });
  tool_call (s, 2, "buffer_open", { { "name", "b" } });

  tool_call (s, 3, "buffer_insert",
	     { { "name", "a" }, { "text", "AAA" } });
  tool_call (s, 4, "buffer_insert",
	     { { "name", "b" }, { "text", "BBBBB" } });

  json sa = tool_call (s, 5, "buffer_state", { { "name", "a" } });
  json sb = tool_call (s, 6, "buffer_state", { { "name", "b" } });

  json sta = json::parse (tool_text (sa));
  json stb = json::parse (tool_text (sb));

  assert (sta["size"] == 3);
  assert (stb["size"] == 5);

  json ca = tool_call (s, 7, "buffer_content", { { "name", "a" } });
  json cb = tool_call (s, 8, "buffer_content", { { "name", "b" } });
  assert (tool_text (ca) == "AAA");
  assert (tool_text (cb) == "BBBBB");
}

// ============================================================
// Test 15: Buffer marker tracks edits across insertions
// ============================================================
static void
test_marker_tracks_edits ()
{
  EmacsBuffer buffer ("*marker-track*", "Hello");
  Marker marker (&buffer, 3, MarkerInsertionType::AFTER_INSERTION);
  assert (marker.position () == 3);

  buffer.set_point (1);
  buffer.insert_string ("XX");
  assert (marker.position () == 5);

  buffer.set_point (5);
  buffer.insert_char ('Y');
  assert (marker.position () == 6);
}

// ============================================================
// Main
// ============================================================
int
main ()
{
  printf ("\n=== Phase 8 Integration Tests ===\n\n");

  RUN_TEST (test_mcp_insert_shows_modified);
  RUN_TEST (test_mcp_execute_custom_command);
  RUN_TEST (test_mode_keymap_integration);
  RUN_TEST (test_minor_mode_overrides_major);
  RUN_TEST (test_buffer_mark_via_mcp);
  RUN_TEST (test_buffer_narrowing);
  RUN_TEST (test_buffer_integrated_undo);
  RUN_TEST (test_buffer_undo_redo_roundtrip);
  RUN_TEST (test_mark_exchange);
  RUN_TEST (test_mcp_full_editing_workflow);
  RUN_TEST (test_mode_hooks);
  RUN_TEST (test_mode_parent_keymap);
  RUN_TEST (test_mcp_command_buffer_pipeline);
  RUN_TEST (test_mcp_multiple_buffers_independent);
  RUN_TEST (test_marker_tracks_edits);

  printf ("\n%d/%d Phase 8 integration tests passed.\n\n", passed,
	  passed + failed);
  return failed > 0 ? EXIT_FAILURE : EXIT_SUCCESS;
}
