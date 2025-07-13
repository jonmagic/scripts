# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent"

module GitHubDeepResearchAgentTest
  class AskClarifyingNodeTest < Minitest::Test
    def setup
      @node = GitHubDeepResearchAgent::AskClarifyingNode.new
      @shared = {
        memory: { hits: [{ url: "https://github.com/foo/bar", summary: "Test summary" }] },
        request: "What is the impact of X?",
        models: { fast: "test-model" }
      }
    end

    def test_prep_generates_questions_with_llm_stub
      # Stub Utils.call_llm
      Utils.stub :call_llm, "1. What is your main goal?\n2. What is your timeline?" do
        result = @node.prep(@shared)
        assert_includes result, "1. What is your main goal?"
        assert_includes result, "2. What is your timeline?"
      end
    end

    def test_exec_with_clarifying_qa_file_reads_file
      Tempfile.create(["clarifying_qa", ".txt"]) do |tmp|
        tmp.write("Q1: A1\nQ2: A2")
        tmp.flush
        @shared[:clarifying_qa] = tmp.path
        @node.instance_variable_set(:@shared, @shared)
        result = @node.exec("Q1\nQ2")
        assert_equal "Q1: A1\nQ2: A2", result
      end
    end

    def test_exec_with_editor_stub
      @node.instance_variable_set(:@shared, @shared)
      Utils.stub :edit_text, "Q1: A1\nQ2: A2" do
        result = @node.exec("Q1\nQ2")
        assert_equal "Q1: A1\nQ2: A2", result
      end
    end

    def test_post_stores_clarifications
      shared = {}
      @node.post(shared, "Q1", "A1")
      assert_equal "A1", shared[:clarifications]
    end
  end
end
