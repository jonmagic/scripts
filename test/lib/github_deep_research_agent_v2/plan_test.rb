# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent_v2"

module GitHubDeepResearchAgentV2Test
  class PlanTest < Minitest::Test
    def test_creates_plan_from_hash
      hash = {
        "question" => "What is X?",
        "aspects" => [
          { "id" => "A1", "title" => "Root Cause", "queries" => ["query1", "query2"] }
        ],
        "depth_limit" => 3,
        "breadth_limit" => 5,
        "initial_hypotheses" => ["Hypothesis 1"],
        "success_criteria" => ["Answer question"]
      }

      plan = GitHubDeepResearchAgentV2::Models::Plan.from_h(hash)

      assert_equal "What is X?", plan.question
      assert_equal 1, plan.aspects.length
      assert_equal 3, plan.depth_limit
      assert_equal 5, plan.breadth_limit
    end

    def test_validates_plan_with_valid_data
      plan = GitHubDeepResearchAgentV2::Models::Plan.new(
        question: "Test question",
        aspects: [
          { "id" => "A1", "title" => "Aspect 1", "queries" => ["query1"] }
        ],
        depth_limit: 3,
        breadth_limit: 5
      )

      assert plan.valid?
      assert_empty plan.validation_errors
    end

    def test_validates_plan_with_missing_question
      plan = GitHubDeepResearchAgentV2::Models::Plan.new(
        question: "",
        aspects: [],
        depth_limit: 3,
        breadth_limit: 5
      )

      refute plan.valid?
      assert_includes plan.validation_errors, "Question is required"
    end

    def test_validates_plan_with_invalid_depth
      plan = GitHubDeepResearchAgentV2::Models::Plan.new(
        question: "Test",
        aspects: [],
        depth_limit: 10,
        breadth_limit: 5
      )

      refute plan.valid?
      assert_includes plan.validation_errors, "Depth limit must be between 1 and 5"
    end

    def test_validates_aspect_structure
      plan = GitHubDeepResearchAgentV2::Models::Plan.new(
        question: "Test",
        aspects: [
          { "id" => "A1" } # Missing title and queries
        ],
        depth_limit: 3,
        breadth_limit: 5
      )

      refute plan.valid?
      errors = plan.validation_errors
      assert errors.any? { |e| e.include?("Aspect 0 missing title") }
      assert errors.any? { |e| e.include?("Aspect 0 missing queries") }
    end

    def test_to_h_returns_hash
      plan = GitHubDeepResearchAgentV2::Models::Plan.new(
        question: "Test",
        aspects: [{ "id" => "A1", "title" => "T", "queries" => ["q1"] }],
        depth_limit: 2
      )

      hash = plan.to_h

      assert_equal "Test", hash[:question]
      assert_equal 2, hash[:depth_limit]
      assert_equal 1, hash[:aspects].length
    end
  end
end
