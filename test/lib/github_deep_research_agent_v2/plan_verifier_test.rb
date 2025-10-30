# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent_v2"

module GitHubDeepResearchAgentV2Test
  class PlanVerifierTest < Minitest::Test
    def setup
      @verifier = GitHubDeepResearchAgentV2::PlanVerifier.new
    end

    def test_verifies_valid_plan
      plan_json = {
        question: "What is X?",
        aspects: [
          { id: "A1", title: "Root Cause", queries: ["query1", "query2"] }
        ],
        depth_limit: 3,
        breadth_limit: 5,
        initial_hypotheses: ["Hypothesis 1"],
        success_criteria: ["Criterion 1"]
      }.to_json

      result = @verifier.verify(plan_json)

      assert result[:valid]
      assert_empty result[:errors]
      refute_nil result[:plan]
    end

    def test_rejects_invalid_json
      result = @verifier.verify("not valid json {")

      refute result[:valid]
      assert_includes result[:errors], "Invalid JSON format"
      assert_nil result[:plan]
    end

    def test_rejects_plan_with_missing_question
      plan_json = {
        question: "",
        aspects: [],
        depth_limit: 3,
        breadth_limit: 5
      }.to_json

      result = @verifier.verify(plan_json)

      refute result[:valid]
      assert result[:errors].any? { |e| e.include?("Question is required") }
    end

    def test_rejects_plan_with_too_many_aspects
      aspects = (1..10).map do |i|
        { id: "A#{i}", title: "Title #{i}", queries: ["q#{i}"] }
      end

      plan_json = {
        question: "Test",
        aspects: aspects,
        depth_limit: 3,
        breadth_limit: 5
      }.to_json

      result = @verifier.verify(plan_json)

      refute result[:valid]
      assert result[:errors].any? { |e| e.include?("Too many aspects") }
    end

    def test_rejects_duplicate_queries
      plan_json = {
        question: "Test",
        aspects: [
          { id: "A1", title: "Title 1", queries: ["same query"] },
          { id: "A2", title: "Title 2", queries: ["same query"] }
        ],
        depth_limit: 3,
        breadth_limit: 5
      }.to_json

      result = @verifier.verify(plan_json)

      refute result[:valid]
      assert result[:errors].any? { |e| e.include?("Duplicate queries") }
    end

    def test_rejects_aspect_with_empty_queries
      plan_json = {
        question: "Test",
        aspects: [
          { id: "A1", title: "Title 1", queries: [""] }
        ],
        depth_limit: 3,
        breadth_limit: 5
      }.to_json

      result = @verifier.verify(plan_json)

      refute result[:valid]
      assert result[:errors].any? { |e| e.include?("empty queries") }
    end
  end
end
