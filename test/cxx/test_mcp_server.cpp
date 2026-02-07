/* test_mcp_server.cpp — MCP server unit tests
   Phase 8.2 — ≥17 tests for McpServer JSON-RPC
   interface.  */

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>

#include "emacs_command_registry.hpp"
#include "emacs_mcp_server.hpp"

#include <nlohmann/json.hpp>

using json = nlohmann::json;
using emacs::McpServer;

/* --- lisp_malloc stubs for GC-aware allocator --- */
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

/* ---- Tests ---- */

static int passed = 0;
static int failed = 0;

#define RUN_TEST(fn)           \
  do                           \
    {                          \
      printf ("  %-50s", #fn); \
      fflush (stdout);         \
      fn ();                   \
      ++passed;                \
      printf ("✓\n");          \
    }                          \
  while (0)

/* 1. Initialize handshake */
static void
test_initialize ()
{
  McpServer s;
  json req = { { "jsonrpc", "2.0" },
	       { "id", 1 },
	       { "method", "initialize" },
	       { "params", json::object () } };
  json resp = parse_response (call (s, req));
  assert (resp["id"] == 1);
  assert (resp["result"]["protocolVersion"] == "2024-11-05");
  assert (resp["result"]["serverInfo"]["name"] == "emacs-mcp");
  assert (resp["result"]["serverInfo"]["version"] == "0.1.0");
  assert (resp["result"]["capabilities"].contains ("tools"));
}

/* 2. tools/list returns all 9 tools */
static void
test_tools_list ()
{
  McpServer s;
  json req = { { "jsonrpc", "2.0" },
	       { "id", 2 },
	       { "method", "tools/list" },
	       { "params", json::object () } };
  json resp = parse_response (call (s, req));
  const auto &tools = resp["result"]["tools"];
  assert (tools.is_array ());
  assert (tools.size () == 9);

  /* Verify tool names */
  std::vector<std::string> names;
  for (const auto &t : tools)
    {
      names.push_back (t["name"].get<std::string> ());
    }
  auto has = [&] (const char *n)
    {
      for (const auto &name : names)
	if (name == n)
	  return true;
      return false;
    };
  assert (has ("buffer_open"));
  assert (has ("buffer_list"));
  assert (has ("buffer_content"));
  assert (has ("buffer_insert"));
  assert (has ("buffer_delete"));
  assert (has ("execute_command"));
  assert (has ("cursor_get"));
  assert (has ("cursor_set"));
  assert (has ("buffer_state"));
}

/* 3. buffer_open creates buffer */
static void
test_buffer_open ()
{
  McpServer s;
  json resp
    = tool_call (s, 3, "buffer_open", { { "name", "scratch" } });
  assert (resp["id"] == 3);
  assert (tool_text (resp) == "Opened buffer: scratch");
}

/* 4. buffer_open — duplicate is OK */
static void
test_buffer_open_duplicate ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "dup" } });
  json resp = tool_call (s, 2, "buffer_open", { { "name", "dup" } });
  assert (tool_text (resp) == "Buffer already exists: dup");
}

/* 5. buffer_list shows created buffers */
static void
test_buffer_list ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "alpha" } });
  tool_call (s, 2, "buffer_open", { { "name", "beta" } });
  json resp = tool_call (s, 3, "buffer_list", json::object ());
  std::string text = tool_text (resp);
  json buffers = json::parse (text);
  assert (buffers.is_array ());
  assert (buffers.size () == 2);
}

/* 6. buffer_content returns text */
static void
test_buffer_content ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "buf1" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "buf1" }, { "text", "hello world" } });
  json resp
    = tool_call (s, 3, "buffer_content", { { "name", "buf1" } });
  assert (tool_text (resp) == "hello world");
}

/* 7. buffer_insert at explicit position */
static void
test_buffer_insert_at_position ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "ins" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "ins" }, { "text", "AC" } });
  tool_call (s, 3, "buffer_insert",
	     { { "name", "ins" },
	       { "text", "B" },
	       { "position", 2 } });
  json resp
    = tool_call (s, 4, "buffer_content", { { "name", "ins" } });
  assert (tool_text (resp) == "ABC");
}

/* 8. buffer_insert at point (no position) */
static void
test_buffer_insert_at_point ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "pt" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "pt" }, { "text", "hello" } });
  json resp = tool_call (s, 3, "buffer_insert",
			 { { "name", "pt" }, { "text", " world" } });
  assert (tool_text (resp) == "Inserted text at point");
  json content
    = tool_call (s, 4, "buffer_content", { { "name", "pt" } });
  assert (tool_text (content) == "hello world");
}

/* 9. buffer_delete range */
static void
test_buffer_delete ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "del" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "del" }, { "text", "abcdef" } });
  json resp
    = tool_call (s, 3, "buffer_delete",
		 { { "name", "del" }, { "start", 2 }, { "end", 4 } });
  assert (tool_text (resp) == "Deleted range");
  json content
    = tool_call (s, 4, "buffer_content", { { "name", "del" } });
  assert (tool_text (content) == "adef");
}

/* 10. cursor_get returns point */
static void
test_cursor_get ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "cur" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "cur" }, { "text", "test" } });
  json resp = tool_call (s, 3, "cursor_get", { { "name", "cur" } });
  json cursor = json::parse (tool_text (resp));
  assert (cursor["point"].get<int> () >= 1);
}

/* 11. cursor_set moves point */
static void
test_cursor_set ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "cs" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "cs" }, { "text", "hello" } });
  json resp = tool_call (s, 3, "cursor_set",
			 { { "name", "cs" }, { "position", 3 } });
  assert (tool_text (resp) == "Cursor moved");
  json get = tool_call (s, 4, "cursor_get", { { "name", "cs" } });
  json cursor = json::parse (tool_text (get));
  assert (cursor["point"] == 3);
}

/* 12. buffer_state returns full state */
static void
test_buffer_state ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "st" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "st" }, { "text", "data" } });
  json resp = tool_call (s, 3, "buffer_state", { { "name", "st" } });
  json state = json::parse (tool_text (resp));
  assert (state.contains ("modified"));
  assert (state.contains ("point"));
  assert (state.contains ("mark"));
  assert (state.contains ("narrowed"));
  assert (state.contains ("mark_active"));
  assert (state.contains ("size"));
  assert (state["size"] == 4);
}

/* 13. execute_command runs registered command */
static void
test_execute_command ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "cmd" } });

  /* Register a simple test command */
  static bool cmd_ran = false;
  cmd_ran = false;
  auto &registry = emacs::CommandRegistry::instance ();
  registry.register_command (
    "test-mcp-cmd", [] (emacs::CommandContext &) { cmd_ran = true; },
    "Test command for MCP", "", 0, 0);

  json resp
    = tool_call (s, 2, "execute_command",
		 { { "name", "test-mcp-cmd" }, { "buffer", "cmd" } });
  assert (tool_text (resp) == "Executed command: test-mcp-cmd");
  assert (cmd_ran);
}

/* 14. Error: unknown method → -32601 */
static void
test_error_unknown_method ()
{
  McpServer s;
  json req = { { "jsonrpc", "2.0" },
	       { "id", 99 },
	       { "method", "bogus/method" },
	       { "params", json::object () } };
  json resp = parse_response (call (s, req));
  assert (resp["error"]["code"] == -32601);
  assert (resp["error"]["message"] == "Method not found");
}

/* 15. Error: unknown buffer → -32602 */
static void
test_error_unknown_buffer ()
{
  McpServer s;
  json resp = tool_call (s, 10, "buffer_content",
			 { { "name", "nonexistent" } });
  assert (resp["error"]["code"] == -32602);
}

/* 16. Error: parse error (malformed JSON) → -32700 */
static void
test_error_parse_error ()
{
  McpServer s;
  std::string resp = s.handle_message ("{ this is not json !!!");
  json r = parse_response (resp);
  assert (r["error"]["code"] == -32700);
  assert (r["error"]["message"] == "Parse error");
}

/* 17. Notification (no id) returns empty string */
static void
test_notification_returns_empty ()
{
  McpServer s;
  json req = { { "jsonrpc", "2.0" },
	       { "method", "notifications/initialized" } };
  std::string resp = call (s, req);
  assert (resp.empty ());
}

/* 18. buffer_content with start/end range */
static void
test_buffer_content_range ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "rng" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "rng" }, { "text", "abcdefgh" } });
  json resp
    = tool_call (s, 3, "buffer_content",
		 { { "name", "rng" }, { "start", 2 }, { "end", 5 } });
  std::string text = tool_text (resp);
  /* content_range(2,5) on "abcdefgh" → "bcd" */
  assert (text == "bcd");
}

/* 19. Error: unknown tool → -32602 */
static void
test_error_unknown_tool ()
{
  McpServer s;
  json resp = tool_call (s, 20, "nonexistent_tool", json::object ());
  assert (resp["error"]["code"] == -32602);
}

/* 20. buffer_delete with invalid range (end < start)
 */
static void
test_buffer_delete_invalid_range ()
{
  McpServer s;
  tool_call (s, 1, "buffer_open", { { "name", "inv" } });
  tool_call (s, 2, "buffer_insert",
	     { { "name", "inv" }, { "text", "abcdef" } });
  json resp
    = tool_call (s, 3, "buffer_delete",
		 { { "name", "inv" }, { "start", 5 }, { "end", 2 } });
  assert (resp.contains ("error"));
}

int
main ()
{
  printf ("\n=== MCP Server Tests (Phase 8.2) "
	  "===\n\n");

  RUN_TEST (test_initialize);
  RUN_TEST (test_tools_list);
  RUN_TEST (test_buffer_open);
  RUN_TEST (test_buffer_open_duplicate);
  RUN_TEST (test_buffer_list);
  RUN_TEST (test_buffer_content);
  RUN_TEST (test_buffer_insert_at_position);
  RUN_TEST (test_buffer_insert_at_point);
  RUN_TEST (test_buffer_delete);
  RUN_TEST (test_cursor_get);
  RUN_TEST (test_cursor_set);
  RUN_TEST (test_buffer_state);
  RUN_TEST (test_execute_command);
  RUN_TEST (test_error_unknown_method);
  RUN_TEST (test_error_unknown_buffer);
  RUN_TEST (test_error_parse_error);
  RUN_TEST (test_notification_returns_empty);
  RUN_TEST (test_buffer_content_range);
  RUN_TEST (test_error_unknown_tool);
  RUN_TEST (test_buffer_delete_invalid_range);

  printf ("\n%d/%d tests passed.\n\n", passed, passed + failed);
  return failed > 0 ? EXIT_FAILURE : EXIT_SUCCESS;
}
