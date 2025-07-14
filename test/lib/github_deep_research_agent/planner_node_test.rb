# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent"

module GitHubDeepResearchAgentTest
  class PlannerNodeTest < Minitest::Test
    def setup
      @node = GitHubDeepResearchAgent::PlannerNode.new(logger: Log::NULL)
      @shared = {
        request: "What is the status of X?",
        clarifications: "Please focus on recent activity.",
        models: { fast: "test-model" },
        current_depth: 0,
        max_depth: 2,
        search_modes: ["semantic"],
        memory: {
          hits: [],
          notes: ["Initial note 1", "Initial note 2"],
          search_queries: ["query1", "query2"]
        },
        unsupported_claims: nil
      }
    end

    def test_prep_returns_nil_at_max_depth
      @shared[:current_depth] = 2
      @shared[:max_depth] = 2
      result = @node.prep(@shared)
      assert_nil result
    end

    def test_prep_handles_unsupported_claims
      @shared[:unsupported_claims] = ["Claim 1", "Claim 2"]
      llm_response = { query: "Find evidence for Claim 1 and Claim 2" }
      Utils.stub :fill_template, "prompt" do
        Utils.stub :call_llm, '{"query": "Find evidence for Claim 1 and Claim 2"}' do
          Utils.stub :parse_semantic_search_response, llm_response do
            result = @node.prep(@shared)
            assert_equal llm_response, result
          end
        end
      end
    end

    def test_prep_semantic_mode
      Utils.stub :fill_template, "prompt" do
        call_llm_mock = proc { '{"query": "Semantic query"}' }
        Utils.stub :call_llm, call_llm_mock do
          Utils.stub :parse_semantic_search_response, { query: "Semantic query" } do
            result = @node.prep(@shared)
            assert_equal({ semantic: { query: "Semantic query" } }, result)
          end
        end
      end
    end

    def test_prep_keyword_mode
      @shared[:search_modes] = ["keyword"]
      Utils.stub :fill_template, "prompt" do
        Utils.stub :call_llm, "repo:foo is:pr" do
          result = @node.prep(@shared)
          assert_equal({ keyword: "repo:foo is:pr" }, result)
        end
      end
    end

    def test_prep_multiple_modes
      @shared[:search_modes] = ["semantic", "keyword"]
      Utils.stub :fill_template, "prompt" do
        call_llm_responses = ['{"query": "Semantic query"}', "repo:foo is:pr"]
        call_llm_mock = proc { call_llm_responses.shift }
        Utils.stub :call_llm, call_llm_mock do
          Utils.stub :parse_semantic_search_response, { query: "Semantic query" } do
            result = @node.prep(@shared)
            assert_equal({ semantic: { query: "Semantic query" }, keyword: "repo:foo is:pr" }, result)
          end
        end
      end
    end

    def test_exec_returns_nil_if_query_nil
      assert_nil @node.exec(nil)
    end

    def test_exec_semantic_mode_structured
      @shared[:search_modes] = ["semantic"]
      @shared[:current_depth] = 1
      @node.instance_variable_set(:@shared, @shared)
      plans = @node.exec({ semantic: { query: "Semantic query", created_after: "2024-01-01" } })
      assert_equal 1, plans.length
      plan = plans.first
      assert_equal :semantic, plan[:tool]
      assert_equal "Semantic query", plan[:query]
      assert_equal "2024-01-01", plan[:created_after]
    end

    def test_exec_keyword_mode_structured
      @shared[:search_modes] = ["keyword"]
      @node.instance_variable_set(:@shared, @shared)
      plans = @node.exec({ keyword: "repo:foo is:pr" })
      assert_equal 1, plans.length
      plan = plans.first
      assert_equal :keyword, plan[:tool]
      assert_equal "repo:foo is:pr", plan[:query]
    end

    def test_exec_multiple_modes_structured
      @shared[:search_modes] = ["semantic", "keyword"]
      @node.instance_variable_set(:@shared, @shared)
      plans = @node.exec({ semantic: { query: "Semantic query", created_after: "2024-01-01" }, keyword: "repo:foo is:pr" })
      assert_equal 2, plans.length

      semantic_plan = plans.find { |p| p[:tool] == :semantic }
      keyword_plan = plans.find { |p| p[:tool] == :keyword }

      assert_equal "Semantic query", semantic_plan[:query]
      assert_equal "2024-01-01", semantic_plan[:created_after]
      assert_equal "repo:foo is:pr", keyword_plan[:query]
    end

    def test_exec_single_query_fallback
      @shared[:search_modes] = ["semantic", "keyword"]
      @node.instance_variable_set(:@shared, @shared)
      plans = @node.exec({ query: "Single query for both modes" })
      assert_equal 2, plans.length

      semantic_plan = plans.find { |p| p[:tool] == :semantic }
      keyword_plan = plans.find { |p| p[:tool] == :keyword }

      assert_equal "Single query for both modes", semantic_plan[:query]
      assert_equal "Single query for both modes", keyword_plan[:query]
    end

    def test_exec_legacy_string_query
      @shared[:search_modes] = ["semantic"]
      @node.instance_variable_set(:@shared, @shared)
      plans = @node.exec("repo:foo is:pr")
      assert_equal 1, plans.length
      plan = plans.first
      assert_equal :semantic, plan[:tool]
      assert_equal "repo:foo is:pr", plan[:query]
    end

    def test_post_final_at_max_depth
      result = @node.post(@shared, nil, nil)
      assert_equal "final", result
    end

    def test_post_sets_next_search_plans
      plans = [{ tool: :semantic, query: "Semantic query" }, { tool: :keyword, query: "Keyword query" }]
      @node.post(@shared, { semantic: { query: "Semantic query" }, keyword: "Keyword query" }, plans)
      assert_equal plans, @shared[:next_search_plans]
    end
  end
end
