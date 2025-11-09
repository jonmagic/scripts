# frozen_string_literal: true

# GitHubDeepResearchAgentV2 - Next-generation deep research agent for GitHub conversations
#
# This module implements a sophisticated research pipeline with:
# - Dynamic multi-aspect planning
# - Parallel search execution
# - External memory management
# - Budget-aware execution
# - Policy-driven decision making
# - Comprehensive source citation

require_relative "github_deep_research_agent_v2/models/plan"
require_relative "github_deep_research_agent_v2/models/artifact"
require_relative "github_deep_research_agent_v2/models/fact"
require_relative "github_deep_research_agent_v2/models/summary"
require_relative "github_deep_research_agent_v2/models/evaluation"
require_relative "github_deep_research_agent_v2/util/json_schema"
require_relative "github_deep_research_agent_v2/util/retry"
require_relative "github_deep_research_agent_v2/util/logging"
require_relative "github_deep_research_agent_v2/budgeting/token_tracker"
require_relative "github_deep_research_agent_v2/memory/artifact_store"
require_relative "github_deep_research_agent_v2/memory/relevance_ranker"
require_relative "github_deep_research_agent_v2/memory/compaction"
require_relative "github_deep_research_agent_v2/plan_verifier"
require_relative "github_deep_research_agent_v2/policy_engine"
require_relative "github_deep_research_agent_v2/planner"
require_relative "github_deep_research_agent_v2/summarizer_agent"
require_relative "github_deep_research_agent_v2/evaluator_agent"
require_relative "github_deep_research_agent_v2/reporter_agent"
require_relative "github_deep_research_agent_v2/search/semantic_search_adapter"
require_relative "github_deep_research_agent_v2/search/keyword_search_adapter"
require_relative "github_deep_research_agent_v2/research_sub_agent"
require_relative "github_deep_research_agent_v2/orchestrator"

module GitHubDeepResearchAgentV2
  VERSION = "2.0.0"

  # Main entry point for the research workflow
  #
  # @param question [String] Research question
  # @param config [Hash] Configuration options
  # @return [Hash] Results with report and metadata
  def self.start(question, config = {})
    # Create orchestrator
    orchestrator = Orchestrator.new(config.merge(question: question))
    
    # Execute workflow
    orchestrator.execute
  end
end
