// src/emacs_event_loop_adapter.hpp
// Phase 5.4: Event Loop Integration
//
// Bridge the C++ EventLoop to Emacs input_event queue.

#pragma once

#include <cstddef>
#include <optional>
#include "containers.hpp"
#include "emacs_input_adapter.hpp"
#include "event_loop.hpp"

namespace emacs
{
namespace tui
{

class EmacsEventLoopAdapter
{
public:
  EmacsEventLoopAdapter ();
  ~EmacsEventLoopAdapter ();

  EmacsEventLoopAdapter (const EmacsEventLoopAdapter &) = delete;
  EmacsEventLoopAdapter &operator= (const EmacsEventLoopAdapter &)
    = delete;

  EmacsEventLoopAdapter (EmacsEventLoopAdapter &&) = delete;
  EmacsEventLoopAdapter &operator= (EmacsEventLoopAdapter &&)
    = delete;

  [[nodiscard]] bool init () noexcept;
  void shutdown () noexcept;

  [[nodiscard]] int process_events () noexcept;
  [[nodiscard]] int wait_for_event (int timeout_ms) noexcept;

  [[nodiscard]] size_t pending_count () const noexcept;

  [[nodiscard]] std::optional<struct input_event>
  peek_event () const noexcept;

  [[nodiscard]] std::optional<struct input_event>
  next_event () noexcept;

  void inject_event (const struct input_event &event);
  void inject_input_event (const InputEvent &event);

  [[nodiscard]] bool is_active () const noexcept;

  void set_current_frame (void *frame) noexcept;
  [[nodiscard]] void *current_frame () const noexcept;

  [[nodiscard]] size_t total_events_processed () const noexcept;

private:
  void on_event (const InputEvent &event) noexcept;
  void push_event (struct input_event event) noexcept;

  EventLoop event_loop_;
  EmacsInputAdapter input_adapter_;
  gc_deque<struct input_event> kbd_buffer_;
  void *current_frame_;
  size_t total_events_processed_;
  bool initialized_;

  static constexpr size_t MAX_KBD_BUFFER_SIZE = 4096;
};

} // namespace tui
} // namespace emacs

#ifdef __cplusplus
extern "C"
{
#endif

  void *emacs_cxx_create_event_loop_adapter (void);
  void emacs_cxx_destroy_event_loop_adapter (void *adapter_ptr);

  int emacs_cxx_init_event_loop (void *adapter_ptr);
  void emacs_cxx_shutdown_event_loop (void *adapter_ptr);
  int emacs_cxx_process_events (void *adapter_ptr);
  int emacs_cxx_wait_for_event (void *adapter_ptr, int timeout_ms);

  int emacs_cxx_next_event (void *adapter_ptr,
			    struct input_event *out_event);
  int emacs_cxx_peek_event (void *adapter_ptr,
			    struct input_event *out_event);
  int emacs_cxx_pending_count (void *adapter_ptr);

  void emacs_cxx_inject_event (void *adapter_ptr,
			       struct input_event *event);
  void emacs_cxx_set_frame (void *adapter_ptr, void *frame);

#ifdef __cplusplus
}
#endif
