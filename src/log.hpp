// src/log.hpp
// C++20 structured logging system for Emacs
//
// Provides thread-safe, structured logging with multiple output
// levels and destinations. Designed to integrate seamlessly with
// Emacs error reporting while providing modern C++20 features.

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <chrono>
#include <cstdarg>
#include <ctime>
#include <fstream>
#include <iostream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>

namespace emacs
{

enum class LogLevel
{
  TRACE = 0,
  DEBUG = 1,
  INFO = 2,
  WARNING = 3,
  ERROR = 4,
  CRITICAL = 5,
  OFF = 6
};

[[nodiscard]] inline constexpr const char *
log_level_to_string (LogLevel level) noexcept
{
  switch (level)
    {
    case LogLevel::TRACE:
      return "TRACE";
    case LogLevel::DEBUG:
      return "DEBUG";
    case LogLevel::INFO:
      return "INFO";
    case LogLevel::WARNING:
      return "WARN";
    case LogLevel::ERROR:
      return "ERROR";
    case LogLevel::CRITICAL:
      return "CRIT";
    case LogLevel::OFF:
      return "OFF";
    default:
      return "UNKNOWN";
    }
}

[[nodiscard]] inline LogLevel
string_to_log_level (std::string_view level) noexcept
{
  if (level == "TRACE" || level == "trace")
    return LogLevel::TRACE;
  if (level == "DEBUG" || level == "debug")
    return LogLevel::DEBUG;
  if (level == "INFO" || level == "info")
    return LogLevel::INFO;
  if (level == "WARNING" || level == "warning" || level == "WARN"
      || level == "warn")
    return LogLevel::WARNING;
  if (level == "ERROR" || level == "error")
    return LogLevel::ERROR;
  if (level == "CRITICAL" || level == "critical" || level == "CRIT"
      || level == "crit")
    return LogLevel::CRITICAL;
  if (level == "OFF" || level == "off")
    return LogLevel::OFF;
  return LogLevel::INFO;
}

struct LogRecord
{
  LogLevel level;
  std::chrono::system_clock::time_point timestamp;
  std::thread::id thread_id;
  std::string_view filename;
  int line;
  std::string_view function;
  std::string message;

  [[nodiscard]] std::string format () const
  {
    auto time_t_val
      = std::chrono::system_clock::to_time_t (timestamp);
    std::tm tm_val;
#ifdef _WIN32
    localtime_s (&tm_val, &time_t_val);
#else
    localtime_r (&time_t_val, &tm_val);
#endif

    char time_buf[64];
    std::strftime (time_buf, sizeof (time_buf), "%Y-%m-%d %H:%M:%S",
		   &tm_val);

    std::ostringstream oss;
    oss << time_buf << " [" << log_level_to_string (level) << "] "
	<< filename << ":" << line << " " << function << " - "
	<< message << "\n";
    return oss.str ();
  }
};

class LogSink
{
public:
  virtual ~LogSink () = default;

  virtual void write (const LogRecord &record) = 0;
  virtual void flush () = 0;

  void set_level (LogLevel level) noexcept { level_ = level; }
  [[nodiscard]] LogLevel get_level () const noexcept
  {
    return level_;
  }

protected:
  LogLevel level_{ LogLevel::INFO };
};

class ConsoleSink : public LogSink
{
public:
  ConsoleSink (bool use_colors = true) : use_colors_ (use_colors) {}

  void write (const LogRecord &record) override
  {
    if (record.level < level_)
      return;

    std::string output
      = use_colors_ ? format_colored (record) : record.format ();
    std::cerr << output;
  }

  void flush () override { std::cerr.flush (); }

private:
  [[nodiscard]] std::string
  format_colored (const LogRecord &record) const
  {
    const char *color = get_color_for_level (record.level);
    auto time_t_val
      = std::chrono::system_clock::to_time_t (record.timestamp);
    std::tm tm_val;
#ifdef _WIN32
    localtime_s (&tm_val, &time_t_val);
#else
    localtime_r (&time_t_val, &tm_val);
#endif

    char time_buf[64];
    std::strftime (time_buf, sizeof (time_buf), "%Y-%m-%d %H:%M:%S",
		   &tm_val);

    std::ostringstream oss;
    oss << time_buf << " [" << log_level_to_string (record.level)
	<< "] " << record.filename << ":" << record.line << " "
	<< record.function << " - " << record.message << "\n";

    if (color)
      return std::string (color) + oss.str () + "\033[0m";
    return oss.str ();
  }

  [[nodiscard]] const char *
  get_color_for_level (LogLevel level) const noexcept
  {
    if (!use_colors_)
      return nullptr;

    switch (level)
      {
      case LogLevel::TRACE:
	return "\033[90m";
      case LogLevel::DEBUG:
	return "\033[36m";
      case LogLevel::INFO:
	return "\033[32m";
      case LogLevel::WARNING:
	return "\033[33m";
      case LogLevel::ERROR:
	return "\033[31m";
      case LogLevel::CRITICAL:
	return "\033[35m";
      default:
	return nullptr;
      }
  }

  bool use_colors_;
};

class FileSink : public LogSink
{
public:
  explicit FileSink (const std::string &filename)
  {
    file_.open (filename, std::ios::out | std::ios::app);
    if (!file_.is_open ())
      throw std::runtime_error ("Failed to open log file: "
				+ filename);
  }

  ~FileSink () override
  {
    if (file_.is_open ())
      file_.close ();
  }

  void write (const LogRecord &record) override
  {
    if (record.level < level_)
      return;

    if (file_.is_open ())
      file_ << record.format ();
  }

  void flush () override
  {
    if (file_.is_open ())
      file_.flush ();
  }

private:
  std::ofstream file_;
};

class Logger
{
public:
  static Logger &instance () noexcept
  {
    static Logger logger;
    return logger;
  }

  Logger (const Logger &) = delete;
  Logger &operator= (const Logger &) = delete;
  Logger (Logger &&) = delete;
  Logger &operator= (Logger &&) = delete;

  void set_level (LogLevel level) noexcept { global_level_ = level; }
  [[nodiscard]] LogLevel get_level () const noexcept
  {
    return global_level_;
  }

  void add_sink (std::unique_ptr<LogSink> sink)
  {
    std::lock_guard<std::mutex> lock (mutex_);
    sinks_.push_back (std::move (sink));
  }

  void clear_sinks ()
  {
    std::lock_guard<std::mutex> lock (mutex_);
    sinks_.clear ();
  }

  void log (LogLevel level, std::string_view message,
	    const char *filename = __builtin_FILE (),
	    int line = __builtin_LINE (),
	    const char *function = __builtin_FUNCTION ())
  {
    if (level < global_level_)
      return;

    LogRecord record{ level,
		      std::chrono::system_clock::now (),
		      std::this_thread::get_id (),
		      filename,
		      line,
		      function,
		      std::string (message) };

    std::lock_guard<std::mutex> lock (mutex_);
    for (auto &sink : sinks_)
      {
	sink->write (record);
      }
  }

  void flush ()
  {
    std::lock_guard<std::mutex> lock (mutex_);
    for (auto &sink : sinks_)
      {
	sink->flush ();
      }
  }

private:
  Logger ()
  {
    add_sink (std::make_unique<ConsoleSink> ());
    global_level_ = LogLevel::INFO;
  }

  ~Logger () = default;

  LogLevel global_level_;
  std::vector<std::unique_ptr<LogSink>> sinks_;
  std::mutex mutex_;
};

#define LOG_TRACE(...) \
  emacs::Logger::instance ().log (emacs::LogLevel::TRACE, __VA_ARGS__)
#define LOG_DEBUG(...) \
  emacs::Logger::instance ().log (emacs::LogLevel::DEBUG, __VA_ARGS__)
#define LOG_INFO(...) \
  emacs::Logger::instance ().log (emacs::LogLevel::INFO, __VA_ARGS__)
#define LOG_WARNING(...)                                    \
  emacs::Logger::instance ().log (emacs::LogLevel::WARNING, \
				  __VA_ARGS__)
#define LOG_ERROR(...) \
  emacs::Logger::instance ().log (emacs::LogLevel::ERROR, __VA_ARGS__)
#define LOG_CRITICAL(...)                                    \
  emacs::Logger::instance ().log (emacs::LogLevel::CRITICAL, \
				  __VA_ARGS__)

extern "C"
{
  inline void emacs_log_set_level (int level)
  {
    Logger::instance ().set_level (static_cast<LogLevel> (level));
  }

  [[nodiscard]] inline int emacs_log_get_level ()
  {
    return static_cast<int> (Logger::instance ().get_level ());
  }

  inline void emacs_log_message (int level, const char *message)
  {
    Logger::instance ().log (static_cast<LogLevel> (level),
			     message ? std::string_view (message)
				     : std::string_view ());
  }

  inline void emacs_log_format (int level, const char *format, ...)
  {
    if (!format)
      return;

    va_list args;
    va_start (args, format);

    va_list args_copy;
    va_copy (args_copy, args);
    int size = std::vsnprintf (nullptr, 0, format, args_copy);
    va_end (args_copy);

    if (size < 0)
      {
	va_end (args);
	return;
      }

    std::string buffer (size + 1, '\0');
    std::vsnprintf (buffer.data (), buffer.size (), format, args);
    va_end (args);

    Logger::instance ().log (static_cast<LogLevel> (level), buffer);
  }
}

}
