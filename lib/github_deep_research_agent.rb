# GitHubDeepResearchAgent - Multi-Stage Research Pipeline for GitHub Conversations
#
# ## Architecture Overview
# This module orchestrates a multi-node workflow for deep research on GitHub issues, PRs, and
# discussions. It combines keyword and semantic search, LLM-powered summarization, topic extraction,
# and interactive research loops.
#
# ### Pipeline & Node Roles
# - **PlannerNode**: The central coordinator and "brain" of the workflow. It decomposes the research
#   question into actionable search plans, manages iteration depth, research memory, and routes
#   control to other nodes. All major decisions and workflow branching originate here.
# - **RetrieverNode**: Acts as the "search engine" of the pipeline. It executes search plans
#   (semantic, keyword, or hybrid), fetches and enriches GitHub conversations, and updates research
#   memory for downstream analysis. RetrieverNode is always invoked by PlannerNode and returns
#   results for further planning or reporting.
# - **InitialResearchNode**: Handles initial query parsing and bootstraps the research context.
# - **AskClarifyingNode**: Generates clarifying questions to improve research focus, as directed by
#   PlannerNode.
# - **ContextCompactionNode**: Compacts and prunes context to fit LLM or memory constraints,
#   typically after several research iterations.
#   research is complete.
# - **ClaimVerifierNode**: Verifies claims or hypotheses using retrieved evidence, under
#   PlannerNode's direction.
# - **FinalReportNode**: Synthesizes findings into a final report when PlannerNode determines
# - **EndNode**: Terminates the workflow and returns results.
#
# ### Data Flow
# 1. **PlannerNode** receives the initial research question and generates a search plan.
# 2. **RetrieverNode** executes the plan, retrieving and enriching relevant conversations.
# 3. Results are routed back to **PlannerNode**, which may trigger further planning, clarification,
#    verification, or compaction as needed.
# 4. The workflow continues, with PlannerNode as the central decision-maker, until it determines
#    sufficient information has been gathered, at which point **FinalReportNode** is invoked.
#
# ### Integration Patterns
# - **LLM Integration**: All LLM calls are made via the `llm` CLI (never direct library imports)
# - **Vector Search**: Uses Qdrant for semantic search with flat JSON metadata
# - **GitHub API**: Fetches data via `gh` CLI GraphQL queries
# - **Caching**: Hierarchical cache in `data/` for raw, summary, and topic data
#
# ### Error Handling
# - Each node implements `prep`, `exec`, and `post` with automatic error handling and retry logic
# - Failures in one node do not halt the entire workflow; errors are logged and degraded gracefully
#
# ### Extensibility
# - Add new nodes by subclassing `Pocketflow::Node` and updating the workflow chain
# - All nodes are loosely coupled and communicate via the shared context
#
# For detailed node documentation, see each class in `lib/github_deep_research_agent/`.

require "json"
require "logger"
require "open3"
require "set"
require "shellwords"
require "tempfile"

require_relative "log"
require_relative "pocketflow"
require_relative "utils"

require_relative "github_deep_research_agent/ask_clarifying_node"
require_relative "github_deep_research_agent/context_compaction_node"
require_relative "github_deep_research_agent/claim_verifier_node"
require_relative "github_deep_research_agent/end_node"
require_relative "github_deep_research_agent/final_report_node"
require_relative "github_deep_research_agent/initial_research_node"
require_relative "github_deep_research_agent/planner_node"
require_relative "github_deep_research_agent/retriever_node"
require_relative "github_deep_research_agent/parallel_retriever_node"
require_relative "github_deep_research_agent/parallel_claim_verifier_node"
require_relative "github_deep_research_agent/parallel_research_flow"

module GitHubDeepResearchAgent
  # Start the research workflow with the given options
  #
  # @param request [String] The research request/question
  # @param options [Hash] Configuration options
  # @option options [String] :collection Qdrant collection name (required)
  # @option options [Integer] :limit Max results per search (default: 5)
  # @option options [Integer] :max_depth Max deep-research passes (default: 2)
  # @option options [String] :editor_file Use fixed file instead of Tempfile
  # @option options [String] :clarifying_qa Path to file with clarifying Q&A
  # @option options [Boolean] :verbose Show debug logs (default: false)
  # @option options [Hash] :models LLM model configuration {:fast, :reasoning}
  # @option options [Array<String>] :search_modes Search modes to use (default: ["semantic", "keyword"])
  # @option options [String] :cache_path Root path for caching fetched data
  # @option options [String] :script_dir Directory containing the scripts
  # @option options [Boolean] :parallel Use parallel nodes for better performance (default: false)
  def self.start(request, options = {})
    logger = options[:logger] || Log.logger

    # Validate required arguments
    if request.nil? || request.strip.empty?
      raise ArgumentError, "Empty request provided"
    end

    unless options[:collection]
      raise ArgumentError, "Collection is required"
    end

    # Set up shared context with defaults
    shared = {
      request: request,
      collection: options[:collection],
      top_k: options[:limit] || 5,
      max_depth: options[:max_depth] || 2,
      editor_file: options[:editor_file],
      clarifying_qa: options[:clarifying_qa],
      verbose: options[:verbose] || false,
      search_modes: options[:search_modes] || ["semantic", "keyword"],
      cache_path: options[:cache_path],
      models: options[:models] || {},
      script_dir: options[:script_dir] || File.expand_path(File.dirname(__FILE__) + "/../bin"),
      parallel: options[:parallel] || false
    }

    # Build the workflow with optional parallel nodes
    initial_node = GitHubDeepResearchAgent::InitialResearchNode.new(logger: logger)
    clarify_node = GitHubDeepResearchAgent::AskClarifyingNode.new(logger: logger)
    planner_node = GitHubDeepResearchAgent::PlannerNode.new(logger: logger)

    # Choose retriever node based on parallel option
    retriever_node = if shared[:parallel]
      logger.info "Using parallel retriever for concurrent search execution"
      GitHubDeepResearchAgent::ParallelRetrieverNode.new(logger: logger)
    else
      GitHubDeepResearchAgent::RetrieverNode.new(logger: logger)
    end

    compaction_node = GitHubDeepResearchAgent::ContextCompactionNode.new(logger: logger)

    # Choose claim verifier based on parallel option
    claim_verifier_node = if shared[:parallel]
      logger.info "Using parallel claim verifier for concurrent verification"
      GitHubDeepResearchAgent::ParallelClaimVerifierNode.new(logger: logger)
    else
      GitHubDeepResearchAgent::ClaimVerifierNode.new(logger: logger)
    end

    final_node = GitHubDeepResearchAgent::FinalReportNode.new(logger: logger)
    end_node = GitHubDeepResearchAgent::EndNode.new(logger: logger)

    # Link the nodes
    initial_node.next(clarify_node)
    clarify_node.next(planner_node)
    planner_node.next(retriever_node)
    retriever_node.on("continue", planner_node) # Loop back to planner for next iteration
    retriever_node.on("final", final_node)

    # Add claim verification flow
    final_node.on("verify", claim_verifier_node)  # Route to claim verification after draft report
    final_node.on("complete", end_node)           # Route to clean termination
    claim_verifier_node.on("ok", final_node)     # Continue to final output after verification
    claim_verifier_node.on("fix", planner_node)  # Route back to planner to gather evidence for unsupported claims

    # Add compaction handling
    final_node.on("compact", compaction_node)         # Route to compaction when context too large
    compaction_node.on("retry", final_node)          # Retry final report after compaction
    compaction_node.on("proceed_anyway", final_node) # Proceed with minimal context if compaction fails

    # Set end node as the final termination point
    final_node.next(end_node)

    # Create and run the flow
    flow = Pocketflow::Flow.new(initial_node)

    parallel_mode = shared[:parallel] ? " (parallel mode)" : ""
    logger.info "=== GITHUB CONVERSATIONS RESEARCH AGENT#{parallel_mode} ==="
    logger.info "Request: #{request}"
    logger.info "Collection: #{options[:collection]}"
    logger.info "Max results per search: #{shared[:top_k]}"
    logger.info "Max deep research iterations: #{shared[:max_depth]}"
    logger.info "Fast model: #{shared[:models][:fast] || 'default'}"
    logger.info "Reasoning model: #{shared[:models][:reasoning] || 'default'}"

    flow.run(shared)
  end
end
