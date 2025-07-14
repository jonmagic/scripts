# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent"

module GitHubDeepResearchAgentTest
  class InitialResearchNodeTest < Minitest::Test
    def setup
      @node = GitHubDeepResearchAgent::InitialResearchNode.new(logger: Log::NULL)
      @shared = {
        request: "repo:octocat/Hello-World status update",
        collection: "github-conversations",
        top_k: 2,
        script_dir: "/tmp",
        cache_path: "/tmp/cache"
      }
    end

    def test_prep_runs_semantic_search_and_parses_results
      fake_search_results = [
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/1", "summary" => "Summary 1" }, "score" => 0.9 },
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/2", "summary" => "Summary 2" }, "score" => 0.8 }
      ]
      Utils.stub :build_semantic_query, { semantic_query: "status update", repo_filter: "octocat/Hello-World" } do
        Utils.stub :build_semantic_search_command, "bin/search-github-conversations" do
          Utils.stub :run_cmd, fake_search_results.to_json do
            results = @node.prep(@shared)
            assert_equal 2, results.size
            assert_equal "https://github.com/octocat/Hello-World/issues/1", results[0]["payload"]["url"]
            assert_equal 0.9, results[0]["score"]
          end
        end
      end
    end

    def test_exec_enriches_results_with_conversation_data
      search_results = [
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/1", "summary" => "Summary 1" }, "score" => 0.9 },
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/2", "summary" => "Summary 2" }, "score" => 0.8 }
      ]
      fake_convo = { "issue" => { "title" => "Test Issue" } }
      @node.instance_variable_set(:@shared, @shared)
      Utils.stub :run_cmd_safe, fake_convo.to_json do
        Utils.stub :extract_conversation_metadata, { title: "Test Issue", type: "issue", state: "open", comments_count: 2 } do
          enriched = @node.exec(search_results)
          assert_equal 2, enriched.size
          assert_equal "https://github.com/octocat/Hello-World/issues/1", enriched[0][:url]
          assert_equal fake_convo, enriched[0][:conversation]
        end
      end
    end

    def test_exec_skips_results_without_url
      search_results = [
        { "payload" => { "summary" => "No URL" }, "score" => 0.5 }
      ]
      @node.instance_variable_set(:@shared, @shared)
      enriched = @node.exec(search_results)
      assert_equal 0, enriched.size
    end

    def test_exec_continues_on_fetch_error
      search_results = [
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/1", "summary" => "Summary 1" }, "score" => 0.9 },
        { "payload" => { "url" => "https://github.com/octocat/Hello-World/issues/2", "summary" => "Summary 2" }, "score" => 0.8 }
      ]
      @node.instance_variable_set(:@shared, @shared)
      # First fetch succeeds, second raises error
      call_count = 0
      Utils.stub :run_cmd_safe, proc {
        call_count += 1
        if call_count == 1
          { "issue" => { "title" => "Test Issue" } }.to_json
        else
          raise StandardError, "fetch failed"
        end
      } do
        Utils.stub :extract_conversation_metadata, { title: "Test Issue", type: "issue", state: "open", comments_count: 2 } do
          enriched = @node.exec(search_results)
          assert_equal 1, enriched.size
          assert_equal "https://github.com/octocat/Hello-World/issues/1", enriched[0][:url]
        end
      end
    end

    def test_post_initializes_memory_and_notes
      exec_res = [
        { url: "https://github.com/octocat/Hello-World/issues/1", summary: "Summary 1", score: 0.9, conversation: {} },
        { url: "https://github.com/octocat/Hello-World/issues/2", summary: "Summary 2", score: 0.8, conversation: {} }
      ]
      @node.post(@shared, nil, exec_res)
      assert @shared[:memory]
      assert_equal 2, @shared[:memory][:hits].size
      assert_equal [], @shared[:memory][:notes]
      assert_equal [@shared[:request]], @shared[:memory][:search_queries]
    end
  end
end
