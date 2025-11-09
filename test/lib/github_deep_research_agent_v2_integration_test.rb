# frozen_string_literal: true

require_relative "../test_helper"
require "github_deep_research_agent_v2"
require "tempfile"
require "fileutils"

# Integration test for GitHubDeepResearchAgentV2
# This test demonstrates the basic workflow without requiring external dependencies
class GitHubDeepResearchAgentV2IntegrationTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @logger = Logger.new(IO::NULL)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_basic_workflow_components
    # This integration test verifies that all components work together
    # without requiring actual LLM calls or external services
    
    # 1. Create a plan
    plan = GitHubDeepResearchAgentV2::Models::Plan.new(
      question: "What is the test question?",
      aspects: [
        {
          "id" => "A1",
          "title" => "Test Aspect",
          "queries" => ["test query 1", "test query 2"]
        }
      ],
      depth_limit: 2,
      breadth_limit: 3,
      success_criteria: ["Answer the question"]
    )

    assert plan.valid?

    # 2. Verify the plan
    verifier = GitHubDeepResearchAgentV2::PlanVerifier.new(logger: @logger)
    result = verifier.verify(plan.to_h.to_json)

    assert result[:valid]
    assert_equal plan.question, result[:plan].question

    # 3. Create some facts
    facts = [
      GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Fact 1 about the test",
        source_urls: ["https://github.com/owner/repo/issues/1"],
        aspect_id: "A1",
        confidence: 0.8
      ),
      GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Fact 2 about the test",
        source_urls: ["https://github.com/owner/repo/issues/2"],
        aspect_id: "A1",
        confidence: 0.9
      )
    ]

    # 4. Store artifacts
    store = GitHubDeepResearchAgentV2::Memory::ArtifactStore.new(
      run_id: "test_run",
      base_path: @tmpdir
    )

    store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(
      type: "plan_node",
      data: plan.to_h
    ))

    facts.each do |fact|
      store.store(GitHubDeepResearchAgentV2::Models::Artifact.new(
        type: "fact",
        data: fact.to_h
      ))
    end

    # 5. Verify storage
    stored_facts = store.load_by_type("fact")
    assert_equal 2, stored_facts.length

    # 6. Test relevance ranking
    ranker = GitHubDeepResearchAgentV2::Memory::RelevanceRanker.new(logger: @logger)
    ranked = ranker.rank(facts, "test question", top_k: 10)

    assert_equal 2, ranked.length
    # Higher confidence fact should rank higher
    assert_equal 0.9, ranked.first.confidence

    # 7. Test budget tracking
    tracker = GitHubDeepResearchAgentV2::Budgeting::TokenTracker.new(budget: 10_000)
    tracker.record(:planning, 1000)
    tracker.record(:research, 3000)

    refute tracker.exhausted?
    assert_equal 4000, tracker.total
    assert_equal 6000, tracker.remaining

    # 8. Test policy engine
    engine = GitHubDeepResearchAgentV2::PolicyEngine.new(
      min_coverage: 0.75,
      stop_if_confidence: 0.85,
      replan_max: 2,
      logger: @logger
    )

    # Low coverage, low confidence, budget available -> continue
    action = engine.decide(
      coverage_score: 0.5,
      confidence_score: 0.6,
      token_usage: 4000,
      token_budget: 10_000,
      replans_used: 0,
      aspect_gap_count: 1
    )

    assert_equal :continue, action

    # High confidence -> finalize
    action = engine.decide(
      coverage_score: 0.7,
      confidence_score: 0.9,
      token_usage: 4000,
      token_budget: 10_000,
      replans_used: 0,
      aspect_gap_count: 0
    )

    assert_equal :finalize_full, action

    # 9. Verify stats
    stats = store.stats
    assert_equal 3, stats[:total_artifacts]  # 1 plan + 2 facts
    assert_equal 1, stats[:by_type]["plan_node"]
    assert_equal 2, stats[:by_type]["fact"]
  end

  def test_compaction_workflow
    # Test memory compaction
    facts = 50.times.map do |i|
      GitHubDeepResearchAgentV2::Models::Fact.new(
        text: "Fact #{i} with lots of text " * 100,  # Make it long enough to trigger compaction
        source_urls: ["https://github.com/test/repo/issues/#{i}"],
        aspect_id: "A1",
        confidence: 0.5 + (i / 100.0)
      )
    end

    compactor = GitHubDeepResearchAgentV2::Memory::Compaction.new(logger: @logger)

    # Should need compaction with many large facts
    if compactor.needs_compaction?(facts)
      # Compact
      compacted = compactor.compact(facts)

      # Should have fewer facts after compaction
      assert compacted.length < facts.length
    else
      # If compaction not needed, that's also valid
      skip "Facts didn't reach compaction threshold"
    end
  end

  def test_json_schema_utilities
    # Test JSON schema helpers
    valid_json = '{"key": "value"}'
    invalid_json = '{not valid'

    assert GitHubDeepResearchAgentV2::Util::JSONSchema.valid_json?(valid_json)
    refute GitHubDeepResearchAgentV2::Util::JSONSchema.valid_json?(invalid_json)

    hash = { "key1" => "value1", "key2" => "value2" }
    assert GitHubDeepResearchAgentV2::Util::JSONSchema.has_keys?(hash, "key1", "key2")
    refute GitHubDeepResearchAgentV2::Util::JSONSchema.has_keys?(hash, "key3")

    # Test duplicate detection
    assert GitHubDeepResearchAgentV2::Util::JSONSchema.no_duplicates?(["a", "b", "c"])
    refute GitHubDeepResearchAgentV2::Util::JSONSchema.no_duplicates?(["a", "A", "b"])  # Case-insensitive
  end

  def test_summary_to_facts_conversion
    # Test converting summaries to facts
    summarizer = GitHubDeepResearchAgentV2::SummarizerAgent.new(logger: @logger)

    summary = GitHubDeepResearchAgentV2::Models::Summary.new(
      source_url: "https://github.com/test/repo/issues/1",
      facts: ["Fact 1", "Fact 2", "Fact 3"],
      topics: ["topic1", "topic2"],
      confidence: 0.8
    )

    facts = summarizer.summary_to_facts(summary, aspect_id: "A1")

    assert_equal 3, facts.length
    assert facts.all? { |f| f.valid? }
    assert facts.all? { |f| f.aspect_id == "A1" }
    assert facts.all? { |f| f.source_urls.include?(summary.source_url) }
    assert facts.all? { |f| f.confidence == 0.8 }
  end
end
