# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent_v2"

module GitHubDeepResearchAgentV2Test
  class PolicyEngineTest < Minitest::Test
    def setup
      @engine = GitHubDeepResearchAgentV2::PolicyEngine.new(
        min_coverage: 0.75,
        stop_if_confidence: 0.85,
        replan_max: 2
      )
    end

    def test_finalizes_full_on_high_confidence
      state = {
        coverage_score: 0.6,
        confidence_score: 0.9,
        token_usage: 10_000,
        token_budget: 60_000,
        replans_used: 0,
        aspect_gap_count: 0
      }

      action = @engine.decide(state)

      assert_equal :finalize_full, action
    end

    def test_finalizes_partial_on_budget_exhausted
      state = {
        coverage_score: 0.5,
        confidence_score: 0.5,
        token_usage: 60_000,
        token_budget: 60_000,
        replans_used: 0,
        aspect_gap_count: 2
      }

      action = @engine.decide(state)

      assert_equal :finalize_partial, action
    end

    def test_replans_with_gaps_and_budget
      state = {
        coverage_score: 0.5,
        confidence_score: 0.5,
        token_usage: 10_000,
        token_budget: 60_000,
        replans_used: 0,
        aspect_gap_count: 3
      }

      action = @engine.decide(state)

      assert_equal :replan, action
    end

    def test_continues_with_low_coverage_and_budget
      state = {
        coverage_score: 0.5,
        confidence_score: 0.6,
        token_usage: 20_000,
        token_budget: 60_000,
        replans_used: 0,
        aspect_gap_count: 1
      }

      action = @engine.decide(state)

      assert_equal :continue, action
    end

    def test_finalizes_partial_on_max_replans_with_low_coverage
      state = {
        coverage_score: 0.5,
        confidence_score: 0.6,
        token_usage: 20_000,
        token_budget: 60_000,
        replans_used: 2,
        aspect_gap_count: 1
      }

      action = @engine.decide(state)

      assert_equal :finalize_partial, action
    end

    def test_finalizes_full_on_max_replans_with_good_coverage
      state = {
        coverage_score: 0.8,
        confidence_score: 0.7,
        token_usage: 20_000,
        token_budget: 60_000,
        replans_used: 2,
        aspect_gap_count: 0
      }

      action = @engine.decide(state)

      assert_equal :finalize_full, action
    end
  end
end
