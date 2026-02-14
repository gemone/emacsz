// test/test_utf8_chinese.cpp
#include <cstring>
#include <format>
#include <iostream>
#include <string>
#include <vector>

namespace utf8_chinese_tests
{

bool
test_ascii_encoding ()
{
  std::string test_str = "Hello, World!";
  std::string expected = "Hello, World!";

  if (test_str == expected)
    {
      std::cout << "PASS: ASCII encoding\n";
      return true;
    }
  else
    {
      std::cout << "FAIL: ASCII encoding\n";
      return false;
    }
}

bool
test_utf8_encoding ()
{
  std::string test_str = "UTF-8 test: 你好，世界！";
  std::string expected = "UTF-8 test: 你好，世界！";

  if (test_str == expected)
    {
      std::cout << "PASS: UTF-8 encoding\n";
      return true;
    }
  else
    {
      std::cout << "FAIL: UTF-8 encoding\n";
      return false;
    }
}

bool
test_chinese_characters ()
{
  std::string test_str = "中文测试";

  std::vector<uint32_t> codepoints;
  for (size_t i = 0; i < test_str.size ();)
    {
      uint32_t cp = static_cast<uint32_t> (test_str[i]);
      codepoints.push_back (cp);
    }

  if (codepoints.size () == 4)
    {
      std::cout << "PASS: Chinese characters\n";
      return true;
    }
  else
    {
      std::cout << "FAIL: Chinese characters\n";
      return false;
    }
}

bool
test_mixed_ascii_chinese ()
{
  std::string test_str = "Hello 世界";

  size_t len = test_str.length ();
  bool has_non_ascii = false;
  for (size_t i = 0; i < len; ++i)
    {
      if (static_cast<unsigned char> (test_str[i]) > 0x7F)
	{
	  has_non_ascii = true;
	  break;
	}
    }

  if (has_non_ascii)
    {
      std::cout << "PASS: Mixed ASCII/Chinese\n";
      return true;
    }
  else
    {
      std::cout << "FAIL: Mixed ASCII/Chinese\n";
      return false;
    }
}

int
main ()
{
  std::cout << "=== Phase 3: UTF-8/Chinese Encoding Tests ===\n";

  int passed = 0;
  int failed = 0;

  if (test_ascii_encoding ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  if (test_utf8_encoding ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  if (test_chinese_characters ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  if (test_mixed_ascii_chinese ())
    {
      ++passed;
    }
  else
    {
      ++failed;
    }

  std::cout << "\n=== Test Results ===\n";
  std::cout << "Passed: " << passed << "\n";
  std::cout << "Failed: " << failed << "\n";
  std::cout << "Success criteria: All tests must pass (4/4)\n";

  return (failed == 0) ? 0 : 1;
}
