# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent"

module GitHubDeepResearchAgentTest
  class FinalReportNodeTest < Minitest::Test
    def setup
      @node = GitHubDeepResearchAgent::FinalReportNode.new(logger: Log::NULL)
      @shared = {
        memory: {
          hits: [
            {
              url: "https://github.com/example/repo/issues/1",
              summary: "Summary 1",
              score: 0.9,
              conversation: { "issue" => { "title" => "Issue 1" } }
            },
            {
              url: "https://github.com/example/repo/issues/2",
              summary: "Summary 2",
              score: 0.8,
              conversation: { "issue" => { "title" => "Issue 2" } }
            }
          ],
          search_queries: ["query1", "query2"]
        },
        request: "What is the status of X?",
        clarifications: "Please focus on recent activity.",
        models: { reasoning: "test-model" },
        compaction_attempts: 0,
        current_depth: 2
      }
    end

    def test_prep_generates_prompt
      prompt = @node.prep(@shared)
      assert_includes prompt, "Original Request"
      assert_includes prompt, @shared[:request]
      assert_includes prompt, @shared[:clarifications]
      assert_includes prompt, "Summary 1"
      assert_includes prompt, "Summary 2"
      assert_includes prompt, "https://github.com/example/repo/issues/1"
      assert_includes prompt, "https://github.com/example/repo/issues/2"
    end

    def test_exec_returns_draft_answer
      prompt = "Prompt for LLM"
      # Stub Utils.call_llm to return a fake answer
      @node.instance_variable_set(:@shared, @shared)
      Utils.stub :call_llm, "Draft report" do
        result = @node.exec(prompt)
        assert_equal "Draft report", result
        assert_equal "Draft report", @shared[:draft_answer]
      end
    end

    def test_exec_handles_context_too_large
      prompt = "Prompt for LLM"
      error = StandardError.new("context length exceeded")
      @node.instance_variable_set(:@shared, @shared)
      Utils.stub :call_llm, proc { raise error } do
        Utils.stub :context_too_large_error?, true do
          Utils.stub :rate_limit_error?, false do
            result = @node.exec(prompt)
            assert_equal :context_too_large, result
            assert_equal "context length exceeded", @shared[:last_context_error]
          end
        end
      end
    end

    def test_exec_handles_rate_limit
      prompt = "Prompt for LLM"
      error = StandardError.new("rate limit exceeded")
      @node.instance_variable_set(:@shared, @shared)
      Utils.stub :call_llm, proc { raise error } do
        Utils.stub :context_too_large_error?, false do
          Utils.stub :rate_limit_error?, true do
            result = @node.exec(prompt)
            assert_equal :context_too_large, result
            assert_equal "rate limit exceeded", @shared[:last_context_error]
          end
        end
      end
    end

    def test_exec_reraises_unexpected_error
      prompt = "Prompt for LLM"
      error = StandardError.new("unexpected error")
      @node.instance_variable_set(:@shared, @shared)
      Utils.stub :call_llm, proc { raise error } do
        Utils.stub :context_too_large_error?, false do
          Utils.stub :rate_limit_error?, false do
            @node.logger.stub :error, nil do
              assert_raises(StandardError) { @node.exec(prompt) }
            end
          end
        end
      end
    end

    def test_post_routes_to_compaction
      res = @node.post(@shared, "prompt", :context_too_large)
      assert_equal "compact", res
    end

    def test_post_routes_to_claim_verification
      @shared[:claim_verification_completed] = false
      res = @node.post(@shared, "prompt", "Draft report")
      assert_equal "verify", res
      assert @shared[:claim_verification_completed]
    end

    def test_post_completes_and_prints_final_report
      @shared[:claim_verification_completed] = true
      @shared[:unsupported_claims] = ["Claim 1"]
      @shared[:claim_verification] = { total_claims: 2, supported_claims: ["Claim 2"], unsupported_claims: ["Claim 1"] }
      # Stub puts and logger.info to silence output
      @node.stub :puts, nil do
        @node.logger.stub :info, nil do
          res = @node.post(@shared, "prompt", "Final report text")
          assert_equal "complete", res
        end
      end
    end
  end
end
