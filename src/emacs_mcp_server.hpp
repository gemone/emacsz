#pragma once

#include <string>
#include <string_view>

#include "containers.hpp"
#include "emacs_buffer.hpp"
#include "emacs_command_registry.hpp"

#include "../third_party/nlohmann/json.hpp"

namespace emacs
{

class McpServer
{
public:
  McpServer ();
  ~McpServer ();

  McpServer (const McpServer &) = delete;
  McpServer &operator= (const McpServer &) = delete;
  McpServer (McpServer &&) = delete;
  McpServer &operator= (McpServer &&) = delete;

  [[nodiscard]] std::string
  handle_message (std::string_view json_line);

  void run_stdio_loop ();

private:
  [[nodiscard]] std::string
  handle_initialize (std::string_view id_json) const;

  [[nodiscard]] std::string
  handle_tools_list (std::string_view id_json) const;

  [[nodiscard]] std::string
  handle_tools_call (std::string_view id_json,
		     std::string_view params_json);

  [[nodiscard]] bool tool_buffer_open (std::string_view args_json,
				       std::string &out_text,
				       std::string &out_error);

  [[nodiscard]] bool tool_buffer_list (std::string_view args_json,
				       std::string &out_text,
				       std::string &out_error) const;

  [[nodiscard]] bool tool_buffer_content (std::string_view args_json,
					  std::string &out_text,
					  std::string &out_error);

  [[nodiscard]] bool tool_buffer_insert (std::string_view args_json,
					 std::string &out_text,
					 std::string &out_error);

  [[nodiscard]] bool tool_buffer_delete (std::string_view args_json,
					 std::string &out_text,
					 std::string &out_error);

  [[nodiscard]] bool tool_execute_command (std::string_view args_json,
					   std::string &out_text,
					   std::string &out_error);

  [[nodiscard]] bool tool_cursor_get (std::string_view args_json,
				      std::string &out_text,
				      std::string &out_error);

  [[nodiscard]] bool tool_cursor_set (std::string_view args_json,
				      std::string &out_text,
				      std::string &out_error);

  [[nodiscard]] bool tool_buffer_state (std::string_view args_json,
					std::string &out_text,
					std::string &out_error);

  gc_unordered_map<gc_string, EmacsBuffer *> buffers_;
  emacs_allocator<EmacsBuffer> buffer_allocator_;
  bool initialized_;
};

} // namespace emacs

extern "C"
{
  void *emacs_cxx_create_mcp_server ();
  void emacs_cxx_destroy_mcp_server (void *server);
  const char *emacs_cxx_mcp_handle_message (void *server,
					    const char *json_line);
}
