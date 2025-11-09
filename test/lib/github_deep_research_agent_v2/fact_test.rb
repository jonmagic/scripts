# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent_v2"

module GitHubDeepResearchAgentV2Test
  class FactTest < Minitest::Test
    def test_creates_fact_with_defaults
      fact = GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Test fact",
        source_urls: ["https://github.com/owner/repo/issues/1"]
      )

      assert_equal "Test fact", fact.text
      assert_equal ["https://github.com/owner/repo/issues/1"], fact.source_urls
      refute_nil fact.id
      refute_nil fact.extracted_at
    end

    def test_validates_fact_with_valid_data
      fact = GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Valid fact",
        source_urls: ["https://github.com/test/repo/issues/1"],
        confidence: 0.8
      )

      assert fact.valid?
    end

    def test_validates_fact_with_empty_text
      fact = GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "",
        source_urls: ["https://github.com/test/repo/issues/1"]
      )

      refute fact.valid?
    end

    def test_validates_fact_with_no_sources
      fact = GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Fact without sources",
        source_urls: []
      )

      refute fact.valid?
    end

    def test_validates_fact_with_invalid_confidence
      fact = GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Test fact",
        source_urls: ["https://github.com/test/repo/issues/1"],
        confidence: 1.5
      )

      refute fact.valid?
    end

    def test_generates_deterministic_id
      fact1 = GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Same text",
        source_urls: ["url1"]
      )

      fact2 = GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Same text",
        source_urls: ["url2"]
      )

      assert_equal fact1.id, fact2.id
    end

    def test_to_h_returns_flat_hash
      fact = GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Test",
        source_urls: ["url1", "url2"],
        aspect_id: "A1",
        confidence: 0.9
      )

      hash = fact.to_h

      assert_equal "Test", hash[:text]
      assert_equal ["url1", "url2"], hash[:source_urls]
      assert_equal "A1", hash[:aspect_id]
      assert_equal 0.9, hash[:confidence]
    end

    def test_token_count_estimation
      fact = GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "a" * 100,
        source_urls: ["url1"]
      )

      # Rough estimate: 100 chars / 4 = 25 tokens
      assert_equal 25, fact.token_count
    end
  end
end
