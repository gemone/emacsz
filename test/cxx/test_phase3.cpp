#include "containers.hpp"
#include "log.hpp"
#include "platform.hpp"
#include "terminal_database.hpp"

#include <cassert>
#include <iostream>

using namespace emacs;

void
test_log_levels ()
{
  std::cout << "Testing log levels..." << std::endl;

  assert (string_to_log_level ("TRACE") == LogLevel::TRACE);
  assert (string_to_log_level ("DEBUG") == LogLevel::DEBUG);
  assert (string_to_log_level ("INFO") == LogLevel::INFO);
  assert (string_to_log_level ("WARNING") == LogLevel::WARNING);
  assert (string_to_log_level ("ERROR") == LogLevel::ERROR);
  assert (string_to_log_level ("CRITICAL") == LogLevel::CRITICAL);
  assert (string_to_log_level ("trace") == LogLevel::TRACE);
  assert (string_to_log_level ("debug") == LogLevel::DEBUG);
  assert (string_to_log_level ("info") == LogLevel::INFO);
  assert (string_to_log_level ("warn") == LogLevel::WARNING);
  assert (string_to_log_level ("error") == LogLevel::ERROR);
  assert (string_to_log_level ("crit") == LogLevel::CRITICAL);

  assert (std::string (log_level_to_string (LogLevel::TRACE))
	  == "TRACE");
  assert (std::string (log_level_to_string (LogLevel::DEBUG))
	  == "DEBUG");
  assert (std::string (log_level_to_string (LogLevel::INFO))
	  == "INFO");
  assert (std::string (log_level_to_string (LogLevel::WARNING))
	  == "WARN");
  assert (std::string (log_level_to_string (LogLevel::ERROR))
	  == "ERROR");
  assert (std::string (log_level_to_string (LogLevel::CRITICAL))
	  == "CRIT");

  std::cout << "  Log level conversion: PASSED" << std::endl;
}

void
test_logger ()
{
  std::cout << "Testing logger..." << std::endl;

  Logger &logger = Logger::instance ();
  logger.set_level (LogLevel::DEBUG);

  logger.log (LogLevel::INFO, "Test message");
  logger.log (LogLevel::WARNING, "Warning message");
  logger.log (LogLevel::ERROR, "Error message");

  std::cout << "  Logger basic operations: PASSED" << std::endl;
}

void
test_platform_detection ()
{
  std::cout << "Testing platform detection..." << std::endl;

  Platform platform = get_platform ();
  Architecture arch = get_architecture ();

  assert (platform != Platform::UNKNOWN);
  assert (arch != Architecture::UNKNOWN);

  assert (is_unix () || is_windows ());
  assert (is_64bit ());

  std::cout << "  Platform: " << get_platform_name () << std::endl;
  std::cout << "  Architecture: " << get_architecture_name ()
	    << std::endl;
  std::cout << "  Platform detection: PASSED" << std::endl;
}

void
test_platform_features ()
{
  std::cout << "Testing platform features..." << std::endl;

  PlatformFeatures features = get_platform_features ();

  std::cout << "  POSIX threads: " << features.has_posix_threads
	    << std::endl;
  std::cout << "  Pthreads: " << features.has_pthreads << std::endl;
  std::cout << "  Termios: " << features.has_termios << std::endl;
  std::cout << "  Platform features: PASSED" << std::endl;
}

void
test_gc_containers ()
{
  std::cout << "Testing GC-aware containers..." << std::endl;

  gc_vector_t<int> vec;
  vec.push_back (1);
  vec.push_back (2);
  vec.push_back (3);

  assert (vec.size () == 3);
  assert (vec[0] == 1);
  assert (vec[1] == 2);
  assert (vec[2] == 3);

  gc_map<int, std::string> map;
  map[1] = "one";
  map[2] = "two";
  map[3] = "three";

  assert (map.size () == 3);
  assert (map[1] == "one");
  assert (map[2] == "two");
  assert (map[3] == "three");

  gc_set<int> set;
  set.insert (1);
  set.insert (2);
  set.insert (3);

  assert (set.size () == 3);
  assert (set.count (1) == 1);
  assert (set.count (2) == 1);
  assert (set.count (3) == 1);

  std::cout << "  GC containers: PASSED" << std::endl;
}

void
test_terminal_database ()
{
  std::cout << "Testing terminal database..." << std::endl;

  TerminalDatabase &db = TerminalDatabase::instance ();
  db.set_terminal_type ("vt100");

  assert (db.is_vt100 ());
  assert (!db.is_xterm ());
  assert (db.get_term_type () == "vt100");

  db.set_terminal_type ("xterm");
  assert (!db.is_vt100 ());
  assert (db.is_xterm ());
  assert (db.get_term_type () == "xterm");

  db.set_terminal_type ("screen");
  assert (db.is_screen ());
  assert (db.get_term_type () == "screen");

  TerminalCapabilities caps = db.get_capabilities ();
  assert (caps.colors >= 8);
  assert (caps.max_width > 0);
  assert (caps.max_height > 0);

  std::cout << "  Terminal database: PASSED" << std::endl;
}

void
test_c_compatibility ()
{
  std::cout << "Testing C compatibility..." << std::endl;

  Logger::instance ().set_level (LogLevel::INFO);

  emacs_log_set_level (static_cast<int> (LogLevel::DEBUG));
  assert (emacs_log_get_level ()
	  == static_cast<int> (LogLevel::DEBUG));

  emacs_log_message (static_cast<int> (LogLevel::INFO),
		     "C compatibility test message");

  emacs_log_set_level (static_cast<int> (LogLevel::WARNING));

  std::cout << "  C compatibility: PASSED" << std::endl;
}

int
main ()
{
  std::cout << "=== Phase 3 Unit Tests ===" << std::endl;
  std::cout << std::endl;

  test_log_levels ();
  std::cout << std::endl;

  test_logger ();
  std::cout << std::endl;

  test_platform_detection ();
  std::cout << std::endl;

  test_platform_features ();
  std::cout << std::endl;

  test_gc_containers ();
  std::cout << std::endl;

  test_terminal_database ();
  std::cout << std::endl;

  test_c_compatibility ();
  std::cout << std::endl;

  std::cout << "=== All Tests PASSED ===" << std::endl;

  return 0;
}
