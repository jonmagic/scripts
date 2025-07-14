# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent"

module GitHubDeepResearchAgentTest
  class RetrieverNodeTest < Minitest::Test
    def setup
      @node = GitHubDeepResearchAgent::RetrieverNode.new(logger: Log::NULL)
      @shared = {
        next_search_plans: [{ tool: :semantic, query: "status update" }],
        collection: "github-conversations",
        top_k: 2,
        script_dir: "/tmp",
        cache_path: "/tmp/cache",
        memory: { hits: [] },
        current_depth: 0,
        max_depth: 2
      }
    end

    def test_prep_returns_search_plans
      plans = @node.prep(@shared)
      assert_equal 1, plans.length
      assert_equal :semantic, plans.first[:tool]
      assert_equal "status update", plans.first[:query]
    end

    def test_prep_returns_nil_if_no_plans
      @shared[:next_search_plans] = nil
      assert_nil @node.prep(@shared)
    end

    def test_prep_returns_nil_if_empty_plans
      @shared[:next_search_plans] = []
      assert_nil @node.prep(@shared)
    end

    def test_exec_returns_empty_if_plans_nil
      assert_equal [], @node.exec(nil)
    end

    def test_exec_returns_empty_if_plans_empty
      assert_equal [], @node.exec([])
    end

    def test_exec_semantic_search_and_enrich
      @node.instance_variable_set(:@shared, @shared)
      fake_semantic_results = [
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/1", "summary" => "Summary 1" }, "score" => 0.9 },
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/2", "summary" => "Summary 2" }, "score" => 0.8 }
      ]
      Utils.stub :run_cmd, fake_semantic_results.to_json do
        JSON.stub :parse, fake_semantic_results do
          # Simulate no duplicates in memory
          @shared[:memory][:hits] = []
          # Stub conversation fetch and summary enrichment
          @node.stub :get_or_generate_summary, "Summary 1" do
            @node.stub :extract_conversation_metadata, { title: "Test Issue", type: "issue", state: "open", comments_count: 2 } do
              Utils.stub :run_cmd_safe, { "issue" => { "title" => "Test Issue" } }.to_json do
                enriched = @node.exec(@shared[:next_search_plans])
                assert_equal 2, enriched.size
                assert_equal "https://github.com/octocat/Hello-World/issues/1", enriched[0][:url]
                assert_equal "Summary 1", enriched[0][:summary]
                assert_equal "semantic", enriched[0][:search_mode]
              end
            end
          end
        end
      end
    end

    def test_exec_dedupes_existing_urls
      @node.instance_variable_set(:@shared, @shared)
      fake_semantic_results = [
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/1", "summary" => "Summary 1" }, "score" => 0.9 }
      ]
      @shared[:memory][:hits] = [{ url: "https://github.com/octocat/Hello-World/issues/1" }]
      Utils.stub :run_cmd, fake_semantic_results.to_json do
        JSON.stub :parse, fake_semantic_results do
          enriched = @node.exec(@shared[:next_search_plans])
          assert_equal 0, enriched.size
        end
      end
    end

    def test_exec_handles_fetch_error
      @node.instance_variable_set(:@shared, @shared)
      fake_semantic_results = [
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/1", "summary" => "Summary 1" }, "score" => 0.9 }
      ]
      Utils.stub :run_cmd, fake_semantic_results.to_json do
        JSON.stub :parse, fake_semantic_results do
          @node.stub :get_or_generate_summary, "Summary 1" do
            @node.stub :extract_conversation_metadata, { title: "Test Issue", type: "issue", state: "open", comments_count: 2 } do
              # Simulate fetch error
              Utils.stub :run_cmd_safe, proc { raise StandardError, "fetch failed" } do
                enriched = @node.exec(@shared[:next_search_plans])
                assert_equal 0, enriched.size
              end
            end
          end
        end
      end
    end

    def test_post_final_if_no_plans
      result = @node.post(@shared, nil, [])
      assert_equal "final", result
    end

    def test_post_final_if_empty_plans
      result = @node.post(@shared, [], [])
      assert_equal "final", result
    end

    def test_post_continue_with_new_results
      exec_res = [
        { url: "https://github.com/octocat/Hello-World/issues/1", summary: "Summary 1", score: 0.9, search_mode: "semantic", conversation: {} }
      ]
      search_plans = [{ tool: :semantic, query: "status update" }]
      @shared[:memory][:hits] = []
      @shared[:memory][:notes] = []
      @shared[:memory][:search_queries] = []
      @shared[:current_depth] = 0
      @shared[:max_depth] = 2
      result = @node.post(@shared, search_plans, exec_res)
      assert_equal "continue", result
      assert_equal 1, @shared[:memory][:hits].size
      assert_equal 1, @shared[:memory][:notes].size
      assert_equal 1, @shared[:memory][:search_queries].size
      assert_equal 1, @shared[:current_depth]
    end

    def test_post_final_when_max_depth
      exec_res = [
        { url: "https://github.com/octocat/Hello-World/issues/1", summary: "Summary 1", score: 0.9, search_mode: "semantic", conversation: {} }
      ]
      search_plans = [{ tool: :semantic, query: "status update" }]
      @shared[:memory][:hits] = []
      @shared[:memory][:notes] = []
      @shared[:memory][:search_queries] = []
      @shared[:current_depth] = 1
      @shared[:max_depth] = 1
      result = @node.post(@shared, search_plans, exec_res)
      assert_equal "final", result
      assert_equal 1, @shared[:memory][:hits].size
      assert_equal 1, @shared[:memory][:notes].size
      assert_equal 1, @shared[:memory][:search_queries].size
      assert_equal 2, @shared[:current_depth]
    end
  end
end
