
# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent"

module GitHubDeepResearchAgentTest
  class ClaimVerifierNodeTest < Minitest::Test
    def setup
      @context = {
        draft_answer: "This is a draft answer with two claims.",
        models: { fast: "test-model" },
        collection: "test-collection",
        script_dir: "/tmp",
        verification_attempts: 0
      }
      @node = GitHubDeepResearchAgent::ClaimVerifierNode.new(logger: Log::NULL)
    end

    def test_prep_extracts_claims
      # Stub claim extraction to return fixed claims
      @node.stub :extract_claims_from_report, ["Claim 1", "Claim 2"] do
        claims = @node.prep(@context)
        assert_equal ["Claim 1", "Claim 2"], claims
      end
    end

    def test_exec_verifies_claims_and_returns_results
      # Set up context and stub dependencies
      @node.stub :extract_claims_from_report, ["Claim 1", "Claim 2"] do
        @node.stub :search_evidence_for_claim, ["evidence"] do
          @node.stub :verify_claim_against_evidence, true do
            claims = @node.prep(@context)
            result = @node.exec(claims)
            assert result[:supported_claims].include?("Claim 1")
            assert result[:supported_claims].include?("Claim 2")
            assert_equal [], result[:unsupported_claims]
          end
        end
      end
    end

    def test_post_returns_ok_when_all_claims_supported
      # Simulate a successful verification result
      exec_res = { supported_claims: ["Claim 1", "Claim 2"], unsupported_claims: [] }
      prep_res = ["Claim 1", "Claim 2"]
      result = @node.post(@context, prep_res, exec_res)
      assert_equal "ok", result
      assert_equal exec_res, @context[:claim_verification]
      assert_equal [], @context[:unsupported_claims]
    end

    def test_post_returns_fix_when_unsupported_claims_and_first_attempt
      exec_res = { supported_claims: ["Claim 1"], unsupported_claims: ["Claim 2"] }
      prep_res = ["Claim 1", "Claim 2"]
      @context[:verification_attempts] = 0
      result = @node.post(@context, prep_res, exec_res)
      assert_equal "fix", result
      assert_equal exec_res, @context[:claim_verification]
      assert_equal ["Claim 2"], @context[:unsupported_claims]
      assert_equal 1, @context[:verification_attempts]
    end

    def test_post_returns_ok_when_unsupported_claims_and_max_attempts
      exec_res = { supported_claims: ["Claim 1"], unsupported_claims: ["Claim 2"] }
      prep_res = ["Claim 1", "Claim 2"]
      @context[:verification_attempts] = 1
      result = @node.post(@context, prep_res, exec_res)
      assert_equal "ok", result
      assert_equal exec_res, @context[:claim_verification]
      assert_equal ["Claim 2"], @context[:unsupported_claims]
      assert_equal 1, @context[:verification_attempts]
    end

    def test_full_node_lifecycle_all_supported
      @node.stub :extract_claims_from_report, ["Claim 1", "Claim 2"] do
        @node.stub :search_evidence_for_claim, ["evidence"] do
          @node.stub :verify_claim_against_evidence, true do
            prep_res = @node.prep(@context)
            exec_res = @node.exec(prep_res)
            post_res = @node.post(@context, prep_res, exec_res)
            assert_equal "ok", post_res
            assert_equal ["Claim 1", "Claim 2"], exec_res[:supported_claims]
            assert_equal [], exec_res[:unsupported_claims]
          end
        end
      end
    end
  end
end
