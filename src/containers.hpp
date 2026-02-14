#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "allocator.hpp"

#include <deque>
#include <forward_list>
#include <list>
#include <map>
#include <set>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace emacs
{

using gc_vector = std::vector<char, emacs_allocator<char>>;

template <typename T>
using gc_vector_t = std::vector<T, emacs_allocator<T>>;

using gc_string = std::basic_string<char, std::char_traits<char>,
				    emacs_allocator<char>>;

template <typename T>
using gc_deque = std::deque<T, emacs_allocator<T>>;

template <typename T>
using gc_list = std::list<T, emacs_allocator<T>>;

template <typename T>
using gc_forward_list = std::forward_list<T, emacs_allocator<T>>;

template <
  typename Key, typename Value, typename Compare = std::less<Key>,
  typename Alloc = emacs_allocator<std::pair<const Key, Value>>>
using gc_map = std::map<Key, Value, Compare, Alloc>;

template <typename Key, typename Compare = std::less<Key>>
using gc_set = std::set<Key, Compare, emacs_allocator<Key>>;

template <
  typename Key, typename Value, typename Hash = std::hash<Key>,
  typename KeyEqual = std::equal_to<Key>,
  typename Alloc = emacs_allocator<std::pair<const Key, Value>>>
using gc_unordered_map
  = std::unordered_map<Key, Value, Hash, KeyEqual, Alloc>;

template <typename Key, typename Hash = std::hash<Key>,
	  typename KeyEqual = std::equal_to<Key>>
using gc_unordered_set
  = std::unordered_set<Key, Hash, KeyEqual, emacs_allocator<Key>>;

}
