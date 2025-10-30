# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent_v2"
require "tempfile"

module GitHubDeepResearchAgentV2Test
  class TokenTrackerTest < Minitest::Test
    def test_initializes_with_budget
      tracker = GitHubDeepResearchAgentV2::Budgeting::TokenTracker.new(budget: 50_000)

      assert_equal 50_000, tracker.remaining
      assert_equal 0, tracker.total
    end

    def test_records_usage_by_stage
      tracker = GitHubDeepResearchAgentV2::Budgeting::TokenTracker.new(budget: 10_000)

      tracker.record(:planning, 1000)
      tracker.record(:research, 2000)

      assert_equal 1000, tracker.usage[:planning]
      assert_equal 2000, tracker.usage[:research]
      assert_equal 3000, tracker.total
    end

    def test_calculates_remaining_budget
      tracker = GitHubDeepResearchAgentV2::Budgeting::TokenTracker.new(budget: 10_000)

      tracker.record(:planning, 3000)

      assert_equal 7000, tracker.remaining
    end

    def test_detects_exhausted_budget
      tracker = GitHubDeepResearchAgentV2::Budgeting::TokenTracker.new(budget: 10_000)

      tracker.record(:research, 10_000)

      assert tracker.exhausted?
    end

    def test_detects_near_limit
      tracker = GitHubDeepResearchAgentV2::Budgeting::TokenTracker.new(budget: 10_000)

      tracker.record(:research, 9500)

      assert tracker.near_limit?
    end

    def test_predicts_budget_overflow
      tracker = GitHubDeepResearchAgentV2::Budgeting::TokenTracker.new(budget: 10_000)

      tracker.record(:research, 8000)

      assert tracker.would_exceed?(3000)
      refute tracker.would_exceed?(1500)
    end

    def test_estimates_tokens_from_text
      text = "a" * 400  # 400 characters ~= 100 tokens

      tokens = GitHubDeepResearchAgentV2::Budgeting::TokenTracker.estimate_tokens(text)

      assert_equal 100, tokens
    end

    def test_summary_includes_all_stats
      tracker = GitHubDeepResearchAgentV2::Budgeting::TokenTracker.new(budget: 10_000)
      tracker.record(:planning, 1000)

      summary = tracker.summary

      assert_equal 10_000, summary[:budget]
      assert_equal 1000, summary[:total]
      assert_equal 9000, summary[:remaining]
      assert_equal 10.0, summary[:usage_percentage]
      assert_equal 1000, summary[:breakdown][:planning]
    end
  end
end
