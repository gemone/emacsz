#pragma once

#include <string_view>

namespace emacs
{

struct CommandContext;

// Register all basic editing commands with the CommandRegistry
void register_basic_commands ();

// Individual command functions (exposed for testing/direct use)
void cmd_self_insert (CommandContext &ctx);
void cmd_forward_char (CommandContext &ctx);
void cmd_backward_char (CommandContext &ctx);
void cmd_beginning_of_line (CommandContext &ctx);
void cmd_end_of_line (CommandContext &ctx);
void cmd_delete_char (CommandContext &ctx);
void cmd_backward_delete_char (CommandContext &ctx);
void cmd_newline (CommandContext &ctx);
void cmd_kill_line (CommandContext &ctx);
void cmd_undo (CommandContext &ctx);
void cmd_redo (CommandContext &ctx);
void cmd_beginning_of_buffer (CommandContext &ctx);
void cmd_end_of_buffer (CommandContext &ctx);
void cmd_next_line (CommandContext &ctx);
void cmd_previous_line (CommandContext &ctx);

} // namespace emacs
