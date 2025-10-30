# frozen_string_literal: true

require_relative "../../test_helper"
require "github_deep_research_agent_v2"
require "tempfile"
require "fileutils"

module GitHubDeepResearchAgentV2Test
  class ArtifactStoreTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
      @store = GitHubDeepResearchAgentV2::Memory::ArtifactStore.new(
        run_id: "test_run",
        base_path: @tmpdir
      )
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
    end

    def test_stores_artifact
      artifact = GitHubDeepResearchAgentV2::Models::Artifact.new(
        type: "fact",
        data: { text: "Test fact", source_urls: ["url1"] }
      )

      result = @store.store(artifact)

      assert_equal artifact, result
    end

    def test_loads_all_artifacts
      artifact1 = GitHubDeepResearchAgentV2::Models::Artifact.new(
        type: "fact",
        data: { text: "Fact 1" }
      )
      artifact2 = GitHubDeepResearchAgentV2::Models::Artifact.new(
        type: "summary",
        data: { source_url: "url1" }
      )

      @store.store(artifact1)
      @store.store(artifact2)

      artifacts = @store.load_all

      assert_equal 2, artifacts.length
    end

    def test_loads_artifacts_by_type
      @store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(type: "fact", data: {}))
      @store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(type: "summary", data: {}))
      @store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(type: "fact", data: {}))

      facts = @store.load_by_type("fact")

      assert_equal 2, facts.length
      assert facts.all? { |a| a.type == "fact" }
    end

    def test_queries_artifacts_with_criteria
      @store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(
        type: "fact",
        data: { "aspect_id" => "A1", "text" => "Fact 1" }
      ))
      @store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(
        type: "fact",
        data: { "aspect_id" => "A2", "text" => "Fact 2" }
      ))

      results = @store.query(type: "fact", aspect_id: "A1")

      assert_equal 1, results.length
      assert_equal "A1", results.first.data["aspect_id"]
    end

    def test_counts_by_type
      @store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(type: "fact", data: {}))
      @store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(type: "fact", data: {}))

      count = @store.count_by_type("fact")

      assert_equal 2, count
    end

    def test_stats_returns_summary
      @store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(type: "fact", data: {}))
      @store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(type: "summary", data: {}))

      stats = @store.stats

      assert_equal 2, stats[:total_artifacts]
      assert_equal 1, stats[:by_type]["fact"]
      assert_equal 1, stats[:by_type]["summary"]
    end
  end
end
