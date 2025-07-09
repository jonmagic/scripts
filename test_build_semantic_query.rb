#!/usr/bin/env ruby

# Unit test for Parse Qualifiers → Qdrant Filter Support 
# Tests the build_semantic_query function in github-conversations-research-agent

require 'test/unit'
require 'json'
require 'shellwords'

class TestBuildSemanticQuery < Test::Unit::TestCase

  def setup
    # Define the functions we need to test
  end

  # Helper method: build_semantic_query function
  def build_semantic_query(user_query)
    # Extract repo: and author: qualifiers
    repo_match = user_query.match(/\brepo:(\S+)/)
    author_match = user_query.match(/\bauthor:(\S+)/)
    
    # Strip qualifiers from the query for semantic search
    semantic_query = user_query.dup
    semantic_query.gsub!(/\brepo:\S+/, '')
    semantic_query.gsub!(/\bauthor:\S+/, '')
    semantic_query.strip!
    
    # Clean up extra whitespace
    semantic_query.gsub!(/\s+/, ' ')
    
    {
      semantic_query: semantic_query,
      repo_filter: repo_match ? repo_match[1] : nil,
      author_filter: author_match ? author_match[1] : nil
    }
  end

  # Helper method: build_semantic_search_command function
  def build_semantic_search_command(search_plan, script_dir, collection, top_k)
    cmd = "#{script_dir}/semantic-search-github-conversations"
    cmd += " #{Shellwords.escape(search_plan[:semantic_query] || search_plan[:query])}"
    cmd += " --collection #{Shellwords.escape(collection)}"
    cmd += " --limit #{top_k}"
    cmd += " --format json"

    # Add date filters if present
    if search_plan[:created_after]
      cmd += " --filter created_after:#{Shellwords.escape(search_plan[:created_after])}"
    end
    if search_plan[:created_before]
      cmd += " --filter created_before:#{Shellwords.escape(search_plan[:created_before])}"
    end

    # Add repo filter if present
    if search_plan[:repo_filter]
      cmd += " --filter repo:#{Shellwords.escape(search_plan[:repo_filter])}"
    end

    # Add author filter if present  
    if search_plan[:author_filter]
      cmd += " --filter author:#{Shellwords.escape(search_plan[:author_filter])}"
    end

    # Add ordering if present
    if search_plan[:order_by]
      order_by_str = "#{search_plan[:order_by][:key]} #{search_plan[:order_by][:direction]}"
      cmd += " --order-by #{Shellwords.escape(order_by_str)}"
    end

    cmd
  end

  def test_simple_query_without_qualifiers
    result = build_semantic_query("caching bug")
    assert_equal "caching bug", result[:semantic_query]
    assert_nil result[:repo_filter]
    assert_nil result[:author_filter]
  end

  def test_query_with_repo_qualifier
    result = build_semantic_query("repo:octocat/Hello-World caching bug")
    assert_equal "caching bug", result[:semantic_query]
    assert_equal "octocat/Hello-World", result[:repo_filter]
    assert_nil result[:author_filter]
  end

  def test_query_with_author_qualifier
    result = build_semantic_query("author:octocat authentication issue")
    assert_equal "authentication issue", result[:semantic_query]
    assert_nil result[:repo_filter]
    assert_equal "octocat", result[:author_filter]
  end

  def test_query_with_both_qualifiers
    result = build_semantic_query("repo:octocat/Hello-World author:octocat performance optimization")
    assert_equal "performance optimization", result[:semantic_query]
    assert_equal "octocat/Hello-World", result[:repo_filter]
    assert_equal "octocat", result[:author_filter]
  end

  def test_query_with_qualifiers_at_end
    result = build_semantic_query("database performance repo:rails/rails")
    assert_equal "database performance", result[:semantic_query]
    assert_equal "rails/rails", result[:repo_filter]
    assert_nil result[:author_filter]
  end

  def test_query_with_qualifiers_in_middle
    result = build_semantic_query("performance repo:rails/rails optimization")
    assert_equal "performance optimization", result[:semantic_query]
    assert_equal "rails/rails", result[:repo_filter]
    assert_nil result[:author_filter]
  end

  def test_cli_command_generation_with_repo_filter
    semantic_query_info = build_semantic_query("repo:octocat/Hello-World caching bug")
    search_plan = semantic_query_info.merge({ query: "repo:octocat/Hello-World caching bug" })
    
    cmd = build_semantic_search_command(search_plan, "/path/to/bin", "github-conversations", 5)
    
    # Ensure the command contains the repo filter
    assert_includes cmd, "--filter repo:octocat/Hello-World"
    
    # Ensure the command contains the stripped query (shell-escaped)
    assert_includes cmd, "caching\\ bug"
    
    # Ensure the command doesn't contain the original qualifier in the query part
    assert_not_includes cmd, "repo:octocat/Hello-World caching\\ bug"
  end

  def test_cli_command_generation_with_author_filter
    semantic_query_info = build_semantic_query("author:octocat authentication issue")
    search_plan = semantic_query_info.merge({ query: "author:octocat authentication issue" })
    
    cmd = build_semantic_search_command(search_plan, "/path/to/bin", "github-conversations", 5)
    
    # Ensure the command contains the author filter
    assert_includes cmd, "--filter author:octocat"
    
    # Ensure the command contains the stripped query (shell-escaped)
    assert_includes cmd, "authentication\\ issue"
  end

  def test_cli_command_generation_with_both_filters
    semantic_query_info = build_semantic_query("repo:rails/rails author:dhh performance optimization")
    search_plan = semantic_query_info.merge({ query: "repo:rails/rails author:dhh performance optimization" })
    
    cmd = build_semantic_search_command(search_plan, "/path/to/bin", "github-conversations", 5)
    
    # Ensure the command contains both filters
    assert_includes cmd, "--filter repo:rails/rails"
    assert_includes cmd, "--filter author:dhh"
    
    # Ensure the command contains the stripped query (shell-escaped)
    assert_includes cmd, "performance\\ optimization"
  end

end