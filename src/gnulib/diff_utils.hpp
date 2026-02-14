// src/gnulib/diff_utils.hpp
// C++20 replacement for gnulib diffseq algorithm
// Replaces: diffseq (Myers diff algorithm)

#pragma once

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <algorithm>
#include <cstddef>
#include <functional>
#include <limits>
#include <vector>

namespace emacs::gnulib
{

template <typename Index = std::ptrdiff_t> struct edit_script
{
  enum class operation
  {
    EQUAL,
    INSERT,
    DELETE
  };

  struct entry
  {
    operation op;
    Index x_start;
    Index x_end;
    Index y_start;
    Index y_end;
  };

  std::vector<entry> edits;

  [[nodiscard]] bool empty () const noexcept
  {
    return edits.empty ();
  }

  [[nodiscard]] size_t size () const noexcept
  {
    return edits.size ();
  }

  [[nodiscard]] Index insertions () const noexcept
  {
    Index count = 0;
    for (const auto &e : edits)
      if (e.op == operation::INSERT)
	count += e.y_end - e.y_start;
    return count;
  }

  [[nodiscard]] Index deletions () const noexcept
  {
    Index count = 0;
    for (const auto &e : edits)
      if (e.op == operation::DELETE)
	count += e.x_end - e.x_start;
    return count;
  }
};

namespace detail
{

template <typename Index> struct diff_context
{
  std::vector<Index> v_forward;
  std::vector<Index> v_backward;
  Index offset;

  explicit diff_context (Index max_d)
      : v_forward (2 * static_cast<size_t> (max_d) + 3),
	v_backward (2 * static_cast<size_t> (max_d) + 3),
	offset (max_d + 1)
  {
  }

  Index &fwd (Index k)
  {
    return v_forward[static_cast<size_t> (k + offset)];
  }
  Index &bwd (Index k)
  {
    return v_backward[static_cast<size_t> (k + offset)];
  }
};

} // namespace detail

template <typename RandomIt1, typename RandomIt2,
	  typename Equal = std::equal_to<>>
[[nodiscard]] edit_script<std::ptrdiff_t>
myers_diff (RandomIt1 x_begin, RandomIt1 x_end, RandomIt2 y_begin,
	    RandomIt2 y_end, Equal eq = Equal{})
{
  using Index = std::ptrdiff_t;
  edit_script<Index> result;

  Index n = x_end - x_begin;
  Index m = y_end - y_begin;

  if (n == 0 && m == 0)
    return result;

  if (n == 0)
    {
      result.edits.push_back (
	{ edit_script<Index>::operation::INSERT, 0, 0, 0, m });
      return result;
    }

  if (m == 0)
    {
      result.edits.push_back (
	{ edit_script<Index>::operation::DELETE, 0, n, 0, 0 });
      return result;
    }

  Index max_d = n + m;
  detail::diff_context<Index> ctx (max_d);

  ctx.fwd (1) = 0;

  std::vector<std::vector<Index>> trace;

  for (Index d = 0; d <= max_d; ++d)
    {
      trace.push_back (ctx.v_forward);

      for (Index k = -d; k <= d; k += 2)
	{
	  Index x;
	  if (k == -d
	      || (k != d && ctx.fwd (k - 1) < ctx.fwd (k + 1)))
	    x = ctx.fwd (k + 1);
	  else
	    x = ctx.fwd (k - 1) + 1;

	  Index y = x - k;

	  while (x < n && y < m && eq (x_begin[x], y_begin[y]))
	    {
	      ++x;
	      ++y;
	    }

	  ctx.fwd (k) = x;

	  if (x >= n && y >= m)
	    {
	      Index cx = n;
	      Index cy = m;

	      std::vector<typename edit_script<Index>::entry>
		rev_edits;

	      for (Index dd = d; dd > 0; --dd)
		{
		  const auto &v = trace[static_cast<size_t> (dd)];
		  Index kk = cx - cy;
		  Index px, py;

		  Index v_km1
		    = v[static_cast<size_t> (kk - 1 + max_d + 1)];
		  Index v_kp1
		    = v[static_cast<size_t> (kk + 1 + max_d + 1)];

		  if (kk == -dd || (kk != dd && v_km1 < v_kp1))
		    {
		      px = v_kp1;
		      py = px - (kk + 1);
		    }
		  else
		    {
		      px = v_km1 + 1;
		      py = px - (kk - 1);
		    }

		  while (cx > px && cy > py)
		    {
		      --cx;
		      --cy;
		    }

		  if (cx > px)
		    {
		      rev_edits.push_back (
			{ edit_script<Index>::operation::DELETE, px,
			  cx, py, py });
		    }
		  else if (cy > py)
		    {
		      rev_edits.push_back (
			{ edit_script<Index>::operation::INSERT, px,
			  px, py, cy });
		    }

		  cx = px;
		  cy = py;
		}

	      for (auto it = rev_edits.rbegin ();
		   it != rev_edits.rend (); ++it)
		result.edits.push_back (*it);

	      return result;
	    }
	}
    }

  return result;
}

template <typename T>
[[nodiscard]] edit_script<std::ptrdiff_t>
diff_vectors (const std::vector<T> &a, const std::vector<T> &b)
{
  return myers_diff (a.begin (), a.end (), b.begin (), b.end ());
}

[[nodiscard]] inline edit_script<std::ptrdiff_t>
diff_strings (std::string_view a, std::string_view b)
{
  return myers_diff (a.begin (), a.end (), b.begin (), b.end ());
}

template <typename Index = std::ptrdiff_t> struct lcs_result
{
  std::vector<std::pair<Index, Index>> matches;
  Index length;
};

template <typename RandomIt1, typename RandomIt2,
	  typename Equal = std::equal_to<>>
[[nodiscard]] lcs_result<std::ptrdiff_t>
longest_common_subsequence (RandomIt1 x_begin, RandomIt1 x_end,
			    RandomIt2 y_begin, RandomIt2 y_end,
			    Equal eq = Equal{})
{
  using Index = std::ptrdiff_t;
  lcs_result<Index> result;
  result.length = 0;

  Index n = x_end - x_begin;
  Index m = y_end - y_begin;

  if (n == 0 || m == 0)
    return result;

  std::vector<std::vector<Index>>
    dp (static_cast<size_t> (n + 1),
	std::vector<Index> (static_cast<size_t> (m + 1), 0));

  for (Index i = 1; i <= n; ++i)
    {
      for (Index j = 1; j <= m; ++j)
	{
	  if (eq (x_begin[i - 1], y_begin[j - 1]))
	    dp[static_cast<size_t> (i)][static_cast<size_t> (j)]
	      = dp[static_cast<size_t> (i - 1)]
		  [static_cast<size_t> (j - 1)]
		+ 1;
	  else
	    dp[static_cast<size_t> (i)][static_cast<size_t> (j)]
	      = std::max (dp[static_cast<size_t> (i - 1)]
			    [static_cast<size_t> (j)],
			  dp[static_cast<size_t> (i)]
			    [static_cast<size_t> (j - 1)]);
	}
    }

  result.length
    = dp[static_cast<size_t> (n)][static_cast<size_t> (m)];

  Index i = n, j = m;
  while (i > 0 && j > 0)
    {
      if (eq (x_begin[i - 1], y_begin[j - 1]))
	{
	  result.matches.emplace_back (i - 1, j - 1);
	  --i;
	  --j;
	}
      else if (dp[static_cast<size_t> (i - 1)]
		 [static_cast<size_t> (j)]
	       > dp[static_cast<size_t> (i)]
		   [static_cast<size_t> (j - 1)])
	{
	  --i;
	}
      else
	{
	  --j;
	}
    }

  std::reverse (result.matches.begin (), result.matches.end ());
  return result;
}

template <typename Index = std::ptrdiff_t> struct diff_hunk
{
  Index old_start;
  Index old_count;
  Index new_start;
  Index new_count;
};

template <typename Index>
[[nodiscard]] std::vector<diff_hunk<Index>>
make_hunks (const edit_script<Index> &script, Index context_lines = 3)
{
  std::vector<diff_hunk<Index>> hunks;

  if (script.empty ())
    return hunks;

  diff_hunk<Index> current{};
  bool in_hunk = false;
  Index last_change_end_x = 0;
  Index last_change_end_y = 0;

  for (const auto &edit : script.edits)
    {
      if (edit.op == edit_script<Index>::operation::EQUAL)
	continue;

      if (!in_hunk)
	{
	  current.old_start
	    = std::max (Index (0), edit.x_start - context_lines);
	  current.new_start
	    = std::max (Index (0), edit.y_start - context_lines);
	  in_hunk = true;
	}
      else if (edit.x_start > last_change_end_x + 2 * context_lines)
	{
	  current.old_count
	    = last_change_end_x + context_lines - current.old_start;
	  current.new_count
	    = last_change_end_y + context_lines - current.new_start;
	  hunks.push_back (current);

	  current.old_start
	    = std::max (Index (0), edit.x_start - context_lines);
	  current.new_start
	    = std::max (Index (0), edit.y_start - context_lines);
	}

      last_change_end_x = edit.x_end;
      last_change_end_y = edit.y_end;
    }

  if (in_hunk)
    {
      current.old_count
	= last_change_end_x + context_lines - current.old_start;
      current.new_count
	= last_change_end_y + context_lines - current.new_start;
      hunks.push_back (current);
    }

  return hunks;
}

} // namespace emacs::gnulib
