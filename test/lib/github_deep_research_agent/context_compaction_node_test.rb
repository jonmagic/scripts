# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent"

module GitHubDeepResearchAgentTest
  class ContextCompactionNodeTest < Minitest::Test
    def setup
      @node = GitHubDeepResearchAgent::ContextCompactionNode.new
      @base_hits = Array.new(10) { |i|
        {
          summary: (i.even? ? "Summary #{i}" : nil),
          score: i,
          conversation: {
            "issue" => {
              "title" => "Issue #{i}",
              "state" => "open",
              "url" => "https://github.com/example/repo/issues/#{i}",
              "created_at" => "2025-01-01T00:00:00Z",
              "updated_at" => "2025-01-02T00:00:00Z"
            },
            "comments" => Array.new(i),
            "reviews" => Array.new(i/2),
            "review_comments" => Array.new(i/3)
          }
        }
      }
    end

    def test_prep_conservative_compaction
      shared = { memory: { hits: @base_hits.dup }, compaction_attempts: 0 }
      result = @node.prep(shared)
      assert_equal "Remove bottom 30% by priority", result[:strategy]
      assert_equal 3, result[:removed_count]
      assert_equal 7, result[:remaining_count]
      assert_equal 1, result[:compaction_attempt]
      assert_equal 7, shared[:memory][:hits].size
    end

    def test_prep_aggressive_compaction
      shared = { memory: { hits: @base_hits.dup }, compaction_attempts: 1 }
      result = @node.prep(shared)
      assert_equal "Remove bottom 50% by priority and strip conversation details", result[:strategy]
      assert_equal 5, result[:removed_count]
      assert_equal 5, result[:remaining_count]
      assert_equal 2, result[:compaction_attempt]
      # Check that conversation details are stripped
      shared[:memory][:hits].each do |hit|
        conv = hit[:conversation]
        assert_includes conv.keys, "issue"
        assert_includes conv.keys, "comments_count"
        assert_includes conv.keys, "reviews_count"
        assert_includes conv.keys, "review_comments_count"
        refute_includes conv.keys, "comments"
      end
    end

    def test_prep_final_compaction
      shared = { memory: { hits: @base_hits.dup }, compaction_attempts: 2 }
      result = @node.prep(shared)
      assert_equal "Keep only top 25% with minimal data", result[:strategy]
      assert_equal 7, result[:removed_count]
      assert_equal 3, result[:remaining_count]
      assert_equal 3, result[:compaction_attempt]
    end

    def test_prep_minimal_context
      shared = { memory: { hits: Array.new(3) { |i| { summary: "S#{i}", score: i, conversation: {} } } }, compaction_attempts: 0 }
      result = @node.prep(shared)
      assert_equal "proceed_anyway", result
    end

    def test_prep_max_attempts
      shared = { memory: { hits: @base_hits.dup }, compaction_attempts: 3 }
      result = @node.prep(shared)
      assert_nil result
    end

    def test_exec_and_post_lifecycle
      shared = { memory: { hits: @base_hits.dup }, compaction_attempts: 0 }
      prep_res = @node.prep(shared)
      exec_res = @node.exec(prep_res)
      assert_equal prep_res, exec_res
      # Simulate post (will sleep, so stub sleep)
      @node.stub :sleep, nil do
        post_res = @node.post(shared, prep_res, exec_res)
        assert_equal "retry", post_res
        assert_equal 1, shared[:compaction_attempts]
      end
    end

    def test_exec_proceed_anyway
      assert_equal "proceed_anyway", @node.exec("proceed_anyway")
    end

    def test_exec_nil
      assert_nil @node.exec(nil)
    end

    def test_post_proceed_anyway
      shared = { memory: { hits: @base_hits.dup }, compaction_attempts: 0 }
      assert_equal "proceed_anyway", @node.post(shared, nil, nil)
      assert_equal "proceed_anyway", @node.post(shared, "proceed_anyway", "proceed_anyway")
    end
  end
end
