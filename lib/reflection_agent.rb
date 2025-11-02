# ReflectionAgent - Personal Work Reflection Pipeline (v2)
#
# ## Architecture Overview
# This module orchestrates a hierarchical summarization workflow for creating personal
# work reflections. It starts with curated weekly snippets as the source of truth,
# then expands to include referenced GitHub conversations through clustered summarization.
#
# ### Core Design Principles
# - **Snippets First**: Weekly snippets are the primary signal (you curated them!)
# - **Hierarchical Summarization**: Break large datasets into clusters, summarize each
# - **Bounded Context**: Each LLM call stays under 30KB to avoid context limits
# - **Scalable**: Works for 1 week to 2+ years of reflection
#
# ### Pipeline Stages
# 1. **InitializeNode**: Creates session structure and metadata
# 2. **SnippetsLoaderNode**: Loads all snippets within date range
# 3. **SnippetsClusterNode**: Groups snippets into 4-6 temporal clusters
# 4. **ClusterSnippetSummaryNode**: Summarizes each cluster's snippets (parallel)
# 5. **ConversationsLoaderNode**: Extracts URLs from snippets, loads from vector DB
# 6. **ClusterConversationSummaryNode**: Summarizes conversations per cluster (parallel)
# 7. **FinalSynthesisNode**: Combines all cluster summaries into final reflection
# 8. **EndNode**: Completion summary and next steps
#
# ### Data Flow
# ```
# Snippets (26) → Clusters (5) → Cluster Summaries (5 × 2KB = 10KB)
#                              ↓
# URLs Extracted → Conversations Loaded (260) → Scored → Top 50 per cluster
#                                                       ↓
#                             Cluster Conversation Summaries (5 × 2KB = 10KB)
#                                                       ↓
#                             Final Synthesis (10KB + 10KB = 20KB) ✅
# ```
#
# ### Key Optimizations
# - **Parallel processing**: Cluster summarization uses `ParallelBatchNode`
# - **Smart filtering**: Only top N conversations per cluster reach LLM
# - **Incremental summarization**: Each stage writes checkpoint for resumability
# - **Context preservation**: Original top snippets included in final synthesis
#
# For detailed node documentation, see each class in `lib/reflection_agent/`.

require "json"
require "logger"
require "open3"
require "date"
require "fileutils"
require "shellwords"

require_relative "log"
require_relative "pocketflow"
require_relative "utils"

require_relative "reflection_agent/initialize_node"
require_relative "reflection_agent/snippets_loader_node"
require_relative "reflection_agent/snippets_cluster_node"
require_relative "reflection_agent/cluster_snippet_summary_node"
require_relative "reflection_agent/conversations_loader_node"
require_relative "reflection_agent/cluster_conversation_summary_node"
require_relative "reflection_agent/final_synthesis_node"
require_relative "reflection_agent/end_node"

module ReflectionAgent
  # Start the reflection workflow with the given options
  #
  # @param options [Hash] Configuration options
  # @option options [String] :cache_path Root path for GitHub conversation cache (required)
  # @option options [String] :collection Qdrant collection name (required)
  # @option options [String] :brain_path Path to brain folder with Reflections/, Snippets/, etc. (required)
  # @option options [String] :start_date Start date for reflection (YYYY-MM-DD, default: 14 days ago)
  # @option options [String] :end_date End date for reflection (YYYY-MM-DD, default: today)
  # @option options [String] :purpose Purpose of reflection (default: catch-up)
  # @option options [String] :name Reflection name (default: catch-up-YYYY-MM-DD)
  # @option options [String] :resume_from Resume from existing reflection directory
  # @option options [Boolean] :verbose Show debug logs (default: false)
  # @option options [String] :llm_model LLM model for summaries and synthesis (default: ENV['LLM_MODEL'])
  def self.start(options = {})
    logger = options[:logger] || Log.logger

    # Validate required arguments
    unless options[:cache_path]
      raise ArgumentError, "cache_path is required (path to GitHub conversation cache)"
    end

    unless options[:collection]
      raise ArgumentError, "collection is required (Qdrant collection name)"
    end

    unless options[:brain_path]
      raise ArgumentError, "brain_path is required (path to brain folder)"
    end

    # Validate paths exist
    unless File.directory?(options[:cache_path])
      raise ArgumentError, "cache_path does not exist: #{options[:cache_path]}"
    end

    unless File.directory?(options[:brain_path])
      raise ArgumentError, "brain_path does not exist: #{options[:brain_path]}"
    end

    # Set up shared context
    shared = {
      cache_path: options[:cache_path],
      collection: options[:collection],
      brain_path: options[:brain_path],
      start_date: options[:start_date],
      end_date: options[:end_date],
      purpose: options[:purpose] || "catch-up",
      reflection_name: options[:reflection_name],
      verbose: options[:verbose] || false,
      llm_model: options[:llm_model] || ENV["LLM_MODEL"],
      script_dir: options[:script_dir] || File.expand_path(File.dirname(__FILE__) + "/../bin"),
      resume_from: options[:resume_from],
      executive_summary_prompt_path: options[:executive_summary_prompt_path],
      topics_prompt_path: options[:topics_prompt_path]
    }

    # Build the workflow
    init_node = ReflectionAgent::InitializeNode.new(logger: logger)
    snippets_loader = ReflectionAgent::SnippetsLoaderNode.new(logger: logger)
    snippets_cluster = ReflectionAgent::SnippetsClusterNode.new(logger: logger)
    cluster_snippet_summary = ReflectionAgent::ClusterSnippetSummaryNode.new(logger: logger)
    conversations_loader = ReflectionAgent::ConversationsLoaderNode.new(logger: logger)
    cluster_conversation_summary = ReflectionAgent::ClusterConversationSummaryNode.new(logger: logger)
    final_synthesis = ReflectionAgent::FinalSynthesisNode.new(logger: logger)
    end_node = ReflectionAgent::EndNode.new(logger: logger)

    # Link the nodes in sequence
    init_node.next(snippets_loader)
    snippets_loader.next(snippets_cluster)
    snippets_cluster.next(cluster_snippet_summary)
    cluster_snippet_summary.next(conversations_loader)
    conversations_loader.next(cluster_conversation_summary)
    cluster_conversation_summary.next(final_synthesis)
    final_synthesis.next(end_node)

    # Create and run the flow
    flow = Pocketflow::Flow.new(init_node)

    logger.info "=== PERSONAL WORK REFLECTION AGENT v2 ==="
    logger.info "Strategy: Hierarchical summarization starting with snippets"
    logger.info "Cache path: #{options[:cache_path]}"
    logger.info "Vector collection: #{options[:collection]}"
    logger.info "Brain folder: #{options[:brain_path]}"
    logger.info "LLM model: #{shared[:llm_model] || 'default'}"
    logger.info ""
    logger.info "⚠️  IMPORTANT: Ensure your vector index is up-to-date!"
    logger.info "   This agent will load conversation summaries from Qdrant."
    logger.info ""

    flow.run(shared)
  end
end
