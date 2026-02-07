#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include "emacs_mcp_server.hpp"

#include <iostream>

namespace emacs
{

using json = nlohmann::json;

namespace
{

constexpr const char *k_protocol_version = "2024-11-05";
constexpr const char *k_server_name = "emacs-mcp";
constexpr const char *k_server_version = "0.1.0";

std::string
make_error (const json &id, int code, std::string_view message)
{
  json response;
  response["jsonrpc"] = "2.0";
  response["id"] = id.is_null () ? json () : id;
  response["error"]
    = json{ { "code", code }, { "message", message } };
  return response.dump ();
}

std::string
make_result_text (const json &id, std::string_view text)
{
  json response;
  response["jsonrpc"] = "2.0";
  response["id"] = id;
  response["result"] = json{
    { "content",
      json::array ({ json{ { "type", "text" }, { "text", text } } }) }
  };
  return response.dump ();
}

std::string
make_result_json (const json &id, const json &result)
{
  json response;
  response["jsonrpc"] = "2.0";
  response["id"] = id;
  response["result"] = result;
  return response.dump ();
}

EmacsBuffer *
lookup_buffer (gc_unordered_map<gc_string, EmacsBuffer *> &buffers,
	       const std::string &name)
{
  auto it = buffers.find (gc_string (name.c_str ()));
  if (it == buffers.end ())
    {
      return nullptr;
    }
  return it->second;
}

std::string
format_buffers_list (
  const gc_unordered_map<gc_string, EmacsBuffer *> &buffers)
{
  json result = json::array ();
  for (const auto &entry : buffers)
    {
      result.push_back (entry.first.c_str ());
    }
  return result.dump ();
}

json
tools_schema ()
{
  json tools = json::array ();

  tools.push_back (json{
    { "name", "buffer_open" },
    { "description", "Create a buffer by name." },
    { "inputSchema",
      json{ { "type", "object" },
	    { "properties",
	      json{ { "name", json{ { "type", "string" } } } } },
	    { "required", json::array ({ "name" }) } } } });

  tools.push_back (json{
    { "name", "buffer_list" },
    { "description", "List all buffer names." },
    { "inputSchema", json{ { "type", "object" },
			   { "properties", json::object () },
			   { "required", json::array () } } } });

  tools.push_back (json{
    { "name", "buffer_content" },
    { "description", "Get buffer content." },
    { "inputSchema",
      json{ { "type", "object" },
	    { "properties",
	      json{ { "name", json{ { "type", "string" } } },
		    { "start", json{ { "type", "integer" } } },
		    { "end", json{ { "type", "integer" } } } } },
	    { "required", json::array ({ "name" }) } } } });

  tools.push_back (json{
    { "name", "buffer_insert" },
    { "description", "Insert text into a buffer." },
    { "inputSchema",
      json{ { "type", "object" },
	    { "properties",
	      json{ { "name", json{ { "type", "string" } } },
		    { "text", json{ { "type", "string" } } },
		    { "position", json{ { "type", "integer" } } } } },
	    { "required", json::array ({ "name", "text" }) } } } });

  tools.push_back (json{
    { "name", "buffer_delete" },
    { "description", "Delete a range in a buffer." },
    { "inputSchema",
      json{ { "type", "object" },
	    { "properties",
	      json{ { "name", json{ { "type", "string" } } },
		    { "start", json{ { "type", "integer" } } },
		    { "end", json{ { "type", "integer" } } } } },
	    { "required",
	      json::array ({ "name", "start", "end" }) } } } });

  tools.push_back (json{
    { "name", "execute_command" },
    { "description", "Execute an Emacs command." },
    { "inputSchema",
      json{ { "type", "object" },
	    { "properties",
	      json{ { "name", json{ { "type", "string" } } },
		    { "buffer", json{ { "type", "string" } } } } },
	    { "required", json::array ({ "name" }) } } } });

  tools.push_back (json{
    { "name", "cursor_get" },
    { "description", "Get buffer point." },
    { "inputSchema",
      json{ { "type", "object" },
	    { "properties",
	      json{ { "name", json{ { "type", "string" } } } } },
	    { "required", json::array ({ "name" }) } } } });

  tools.push_back (json{
    { "name", "cursor_set" },
    { "description", "Set buffer point." },
    { "inputSchema",
      json{
	{ "type", "object" },
	{ "properties",
	  json{ { "name", json{ { "type", "string" } } },
		{ "position", json{ { "type", "integer" } } } } },
	{ "required", json::array ({ "name", "position" }) } } } });

  tools.push_back (json{
    { "name", "buffer_state" },
    { "description", "Get buffer state metadata." },
    { "inputSchema",
      json{ { "type", "object" },
	    { "properties",
	      json{ { "name", json{ { "type", "string" } } } } },
	    { "required", json::array () } } } });

  return tools;
}

} // namespace

McpServer::McpServer () : initialized_ (false) {}

McpServer::~McpServer ()
{
  for (auto &entry : buffers_)
    {
      if (entry.second != nullptr)
	{
	  entry.second->~EmacsBuffer ();
	  buffer_allocator_.deallocate (entry.second, 1);
	}
    }
  buffers_.clear ();
}

std::string
McpServer::handle_message (std::string_view json_line)
{
  json request;
  try
    {
      request = json::parse (json_line.begin (), json_line.end ());
    }
  catch (const std::exception &)
    {
      return make_error (json (), -32700, "Parse error");
    }

  if (!request.is_object ())
    {
      return make_error (json (), -32600, "Invalid Request");
    }

  const json id = request.contains ("id") ? request["id"] : json ();
  if (!request.contains ("method") || !request["method"].is_string ())
    {
      return make_error (id, -32600, "Invalid Request");
    }

  const std::string method = request["method"].get<std::string> ();
  if (!request.contains ("id"))
    {
      if (method == "notifications/initialized")
	{
	  initialized_ = true;
	  return "";
	}
      return "";
    }

  if (method == "initialize")
    {
      return handle_initialize (id.dump ());
    }

  if (method == "tools/list")
    {
      return handle_tools_list (id.dump ());
    }

  if (method == "tools/call")
    {
      if (!request.contains ("params")
	  || !request["params"].is_object ())
	{
	  return make_error (id, -32602, "Invalid params");
	}
      return handle_tools_call (id.dump (),
				request["params"].dump ());
    }

  return make_error (id, -32601, "Method not found");
}

void
McpServer::run_stdio_loop ()
{
  std::string line;
  while (std::getline (std::cin, line))
    {
      std::string response = handle_message (line);
      if (!response.empty ())
	{
	  std::cout << response << std::endl;
	}
    }
}

std::string
McpServer::handle_initialize (std::string_view id_json) const
{
  json id = json::parse (id_json.begin (), id_json.end ());
  json result;
  result["protocolVersion"] = k_protocol_version;
  result["capabilities"] = json{ { "tools", json::object () } };
  result["serverInfo"] = json{ { "name", k_server_name },
			       { "version", k_server_version } };
  return make_result_json (id, result);
}

std::string
McpServer::handle_tools_list (std::string_view id_json) const
{
  json id = json::parse (id_json.begin (), id_json.end ());
  json result;
  result["tools"] = tools_schema ();
  return make_result_json (id, result);
}

std::string
McpServer::handle_tools_call (std::string_view id_json,
			      std::string_view params_json)
{
  json id = json::parse (id_json.begin (), id_json.end ());
  json params
    = json::parse (params_json.begin (), params_json.end ());
  if (!params.contains ("name") || !params["name"].is_string ())
    {
      return make_error (id, -32602, "Invalid params");
    }

  const std::string tool_name = params["name"].get<std::string> ();
  json arguments = json::object ();
  if (params.contains ("arguments"))
    {
      arguments = params["arguments"];
    }

  std::string text;
  std::string error;
  bool ok = false;

  if (tool_name == "buffer_open")
    {
      ok = tool_buffer_open (arguments.dump (), text, error);
    }
  else if (tool_name == "buffer_list")
    {
      ok = tool_buffer_list (arguments.dump (), text, error);
    }
  else if (tool_name == "buffer_content")
    {
      ok = tool_buffer_content (arguments.dump (), text, error);
    }
  else if (tool_name == "buffer_insert")
    {
      ok = tool_buffer_insert (arguments.dump (), text, error);
    }
  else if (tool_name == "buffer_delete")
    {
      ok = tool_buffer_delete (arguments.dump (), text, error);
    }
  else if (tool_name == "execute_command")
    {
      ok = tool_execute_command (arguments.dump (), text, error);
    }
  else if (tool_name == "cursor_get")
    {
      ok = tool_cursor_get (arguments.dump (), text, error);
    }
  else if (tool_name == "cursor_set")
    {
      ok = tool_cursor_set (arguments.dump (), text, error);
    }
  else if (tool_name == "buffer_state")
    {
      ok = tool_buffer_state (arguments.dump (), text, error);
    }
  else
    {
      return make_error (id, -32602, "Unknown tool: " + tool_name);
    }

  if (!ok)
    {
      return make_error (id, -32602, error);
    }

  return make_result_text (id, text);
}

bool
McpServer::tool_buffer_open (std::string_view args_json,
			     std::string &out_text,
			     std::string &out_error)
{
  json args = json::parse (args_json.begin (), args_json.end ());
  if (!args.is_object () || !args.contains ("name")
      || !args["name"].is_string ())
    {
      out_error = "Invalid params";
      return false;
    }

  std::string name = args["name"].get<std::string> ();
  if (lookup_buffer (buffers_, name) != nullptr)
    {
      out_text = "Buffer already exists: " + name;
      return true;
    }

  EmacsBuffer *buffer = buffer_allocator_.allocate (1);
  new (buffer) EmacsBuffer (name);
  buffers_.emplace (gc_string (name.c_str ()), buffer);
  out_text = "Opened buffer: " + name;
  return true;
}

bool
McpServer::tool_buffer_list (std::string_view args_json,
			     std::string &out_text,
			     std::string &out_error) const
{
  json args = json::parse (args_json.begin (), args_json.end ());
  if (!args.is_object ())
    {
      out_error = "Invalid params";
      return false;
    }

  out_text = format_buffers_list (buffers_);
  return true;
}

bool
McpServer::tool_buffer_content (std::string_view args_json,
				std::string &out_text,
				std::string &out_error)
{
  json args = json::parse (args_json.begin (), args_json.end ());
  if (!args.is_object () || !args.contains ("name")
      || !args["name"].is_string ())
    {
      out_error = "Invalid params";
      return false;
    }

  std::string name = args["name"].get<std::string> ();
  EmacsBuffer *buffer = lookup_buffer (buffers_, name);
  if (buffer == nullptr)
    {
      out_error = "Buffer not found: " + name;
      return false;
    }

  if (args.contains ("start") && args.contains ("end")
      && args["start"].is_number_integer ()
      && args["end"].is_number_integer ())
    {
      ptrdiff_t start = args["start"].get<ptrdiff_t> ();
      ptrdiff_t end = args["end"].get<ptrdiff_t> ();
      out_text = buffer->content_range (start, end);
      return true;
    }

  out_text = buffer->content ();
  return true;
}

bool
McpServer::tool_buffer_insert (std::string_view args_json,
			       std::string &out_text,
			       std::string &out_error)
{
  json args = json::parse (args_json.begin (), args_json.end ());
  if (!args.is_object () || !args.contains ("name")
      || !args["name"].is_string () || !args.contains ("text")
      || !args["text"].is_string ())
    {
      out_error = "Invalid params";
      return false;
    }

  std::string name = args["name"].get<std::string> ();
  EmacsBuffer *buffer = lookup_buffer (buffers_, name);
  if (buffer == nullptr)
    {
      out_error = "Buffer not found: " + name;
      return false;
    }

  std::string text = args["text"].get<std::string> ();
  bool has_position = false;
  ptrdiff_t position = buffer->point ();
  if (args.contains ("position"))
    {
      if (!args["position"].is_number_integer ())
	{
	  out_error = "Invalid params";
	  return false;
	}
      position = args["position"].get<ptrdiff_t> ();
      has_position = true;
      buffer->set_point (position);
    }

  buffer->insert_string (text);

  if (!has_position)
    {
      out_text = "Inserted text at point";
    }
  else
    {
      out_text = "Inserted text";
      buffer->set_point (position
			 + static_cast<ptrdiff_t> (text.size ()));
    }
  return true;
}

bool
McpServer::tool_buffer_delete (std::string_view args_json,
			       std::string &out_text,
			       std::string &out_error)
{
  json args = json::parse (args_json.begin (), args_json.end ());
  if (!args.is_object () || !args.contains ("name")
      || !args["name"].is_string () || !args.contains ("start")
      || !args.contains ("end") || !args["start"].is_number_integer ()
      || !args["end"].is_number_integer ())
    {
      out_error = "Invalid params";
      return false;
    }

  std::string name = args["name"].get<std::string> ();
  EmacsBuffer *buffer = lookup_buffer (buffers_, name);
  if (buffer == nullptr)
    {
      out_error = "Buffer not found: " + name;
      return false;
    }

  ptrdiff_t start = args["start"].get<ptrdiff_t> ();
  ptrdiff_t end = args["end"].get<ptrdiff_t> ();
  if (end < start)
    {
      out_error = "Invalid params";
      return false;
    }

  buffer->set_point (start);
  buffer->delete_forward (end - start);
  out_text = "Deleted range";
  return true;
}

bool
McpServer::tool_execute_command (std::string_view args_json,
				 std::string &out_text,
				 std::string &out_error)
{
  json args = json::parse (args_json.begin (), args_json.end ());
  if (!args.is_object () || !args.contains ("name")
      || !args["name"].is_string ())
    {
      out_error = "Invalid params";
      return false;
    }

  std::string name = args["name"].get<std::string> ();
  CommandRegistry &registry = CommandRegistry::instance ();
  if (!registry.has_command (name))
    {
      out_error = "Unknown command: " + name;
      return false;
    }

  EmacsBuffer *buffer = nullptr;
  if (args.contains ("buffer"))
    {
      if (!args["buffer"].is_string ())
	{
	  out_error = "Invalid params";
	  return false;
	}
      std::string buffer_name = args["buffer"].get<std::string> ();
      buffer = lookup_buffer (buffers_, buffer_name);
      if (buffer == nullptr)
	{
	  out_error = "Buffer not found: " + buffer_name;
	  return false;
	}
    }
  else if (!buffers_.empty ())
    {
      buffer = buffers_.begin ()->second;
    }

  CommandContext ctx{};
  ctx.buffer = buffer;
  ctx.prefix_argument = 0;
  ctx.has_prefix = false;
  ctx.raw_prefix = false;

  if (!registry.execute (name, ctx))
    {
      out_error = "Command failed: " + name;
      return false;
    }

  out_text = "Executed command: " + name;
  return true;
}

bool
McpServer::tool_cursor_get (std::string_view args_json,
			    std::string &out_text,
			    std::string &out_error)
{
  json args = json::parse (args_json.begin (), args_json.end ());
  if (!args.is_object () || !args.contains ("name")
      || !args["name"].is_string ())
    {
      out_error = "Invalid params";
      return false;
    }

  std::string name = args["name"].get<std::string> ();
  EmacsBuffer *buffer = lookup_buffer (buffers_, name);
  if (buffer == nullptr)
    {
      out_error = "Buffer not found: " + name;
      return false;
    }

  json result{ { "point", buffer->point () } };
  out_text = result.dump ();
  return true;
}

bool
McpServer::tool_cursor_set (std::string_view args_json,
			    std::string &out_text,
			    std::string &out_error)
{
  json args = json::parse (args_json.begin (), args_json.end ());
  if (!args.is_object () || !args.contains ("name")
      || !args["name"].is_string () || !args.contains ("position")
      || !args["position"].is_number_integer ())
    {
      out_error = "Invalid params";
      return false;
    }

  std::string name = args["name"].get<std::string> ();
  EmacsBuffer *buffer = lookup_buffer (buffers_, name);
  if (buffer == nullptr)
    {
      out_error = "Buffer not found: " + name;
      return false;
    }

  buffer->set_point (args["position"].get<ptrdiff_t> ());
  out_text = "Cursor moved";
  return true;
}

bool
McpServer::tool_buffer_state (std::string_view args_json,
			      std::string &out_text,
			      std::string &out_error)
{
  json args = json::parse (args_json.begin (), args_json.end ());
  if (!args.is_object ())
    {
      out_error = "Invalid params";
      return false;
    }

  EmacsBuffer *buffer = nullptr;
  if (args.contains ("name"))
    {
      if (!args["name"].is_string ())
	{
	  out_error = "Invalid params";
	  return false;
	}
      std::string name = args["name"].get<std::string> ();
      buffer = lookup_buffer (buffers_, name);
      if (buffer == nullptr)
	{
	  out_error = "Buffer not found: " + name;
	  return false;
	}
    }
  else if (!buffers_.empty ())
    {
      buffer = buffers_.begin ()->second;
    }

  if (buffer == nullptr)
    {
      out_error = "Invalid params";
      return false;
    }

  json state;
  state["modified"] = buffer->is_modified ();
  state["point"] = buffer->point ();
  state["mark"] = buffer->mark ();
  state["narrowed"] = buffer->is_narrowed ();
  state["mark_active"] = buffer->mark_active ();
  state["size"] = buffer->size ();
  out_text = state.dump ();
  return true;
}

} // namespace emacs

extern "C"
{
  void *emacs_cxx_create_mcp_server ()
  {
    emacs::emacs_allocator<emacs::McpServer> alloc;
    emacs::McpServer *ptr = alloc.allocate (1);
    new (ptr) emacs::McpServer ();
    return ptr;
  }

  void emacs_cxx_destroy_mcp_server (void *server)
  {
    auto *ptr = static_cast<emacs::McpServer *> (server);
    if (ptr == nullptr)
      {
	return;
      }
    ptr->~McpServer ();
    emacs::emacs_allocator<emacs::McpServer> alloc;
    alloc.deallocate (ptr, 1);
  }

  const char *emacs_cxx_mcp_handle_message (void *server,
					    const char *json_line)
  {
    if (server == nullptr || json_line == nullptr)
      {
	return nullptr;
      }
    auto *ptr = static_cast<emacs::McpServer *> (server);
    static thread_local std::string response;
    response = ptr->handle_message (json_line);
    return response.c_str ();
  }
}
