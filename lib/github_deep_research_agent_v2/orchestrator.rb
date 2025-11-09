# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require_relative "models/plan"
require_relative "models/artifact"
require_relative "models/fact"
require_relative "planner"
require_relative "research_sub_agent"
require_relative "evaluator_agent"
require_relative "reporter_agent"
require_relative "policy_engine"
require_relative "memory/artifact_store"
require_relative "memory/relevance_ranker"
require_relative "memory/compaction"
require_relative "budgeting/token_tracker"

module GitHubDeepResearchAgentV2
  # Orchestrator coordinates the entire research workflow
  class Orchestrator
    def initialize(config = {})
      @config = config
      @logger = config[:logger]
      @run_id = generate_run_id(config[:question])
      
      # Initialize components
      @planner = Planner.new(
        logger: @logger,
        max_aspects: config[:max_aspects] || 8,
        breadth_limit: config[:breadth_limit] || 5
      )
      
      @research_agent = ResearchSubAgent.new(
        collection: config[:collection],
        script_dir: config[:script_dir],
        logger: @logger,
        cache_path: config[:cache_path]
      )
      
      @evaluator = EvaluatorAgent.new(logger: @logger)
      @reporter = ReporterAgent.new(logger: @logger)
      
      @policy_engine = PolicyEngine.new(
        min_coverage: config[:min_coverage] || 0.75,
        stop_if_confidence: config[:stop_if_confidence] || 0.85,
        replan_max: config[:replan_max] || 2,
        logger: @logger
      )
      
      @artifact_store = Memory::ArtifactStore.new(
        run_id: @run_id,
        base_path: config[:cache_path] || "./cache/deep_research_v2"
      )
      
      @ranker = Memory::RelevanceRanker.new(logger: @logger)
      @compactor = Memory::Compaction.new(logger: @logger)
      
      @budget_tracker = Budgeting::TokenTracker.new(
        budget: config[:token_budget] || 60_000
      )
      
      # State
      @current_depth = 0
      @replans_used = 0
      @all_facts = []
      @plan = nil
    end

    # Execute the research workflow
    #
    # @return [Hash] Final results with report and metadata
    def execute
      @logger&.info("=== GITHUB DEEP RESEARCH AGENT V2 ===")
      @logger&.info("Run ID: #{@run_id}")
      @logger&.info("Question: #{@config[:question]}")
      
      begin
        # Stage 1: Planning
        @plan = generate_initial_plan
        store_artifact("plan_node", @plan.to_h)
        
        # Stage 2: Execution rounds
        loop do
          break if @current_depth >= (@config[:max_depth] || 3)
          
          @logger&.info("\n--- Depth #{@current_depth + 1} ---")
          
          # Execute research for current depth
          execute_research_round
          
          # Check budget
          if @budget_tracker.exhausted?
            @logger&.warn("Budget exhausted")
            break
          end
          
          # Evaluate progress
          evaluation = evaluate_progress
          store_artifact("evaluation", evaluation.to_h)
          
          # Policy decision
          action = @policy_engine.decide(
            coverage_score: evaluation.aspect_completion,
            confidence_score: evaluation.confidence_score,
            token_usage: @budget_tracker.total,
            token_budget: @config[:token_budget] || 60_000,
            replans_used: @replans_used,
            aspect_gap_count: evaluation.missing_aspects.length
          )
          
          @logger&.info("Policy decision: #{action}")
          
          case action
          when :finalize_full, :finalize_partial
            break
          when :replan
            replan(evaluation.missing_aspects)
          when :continue
            @current_depth += 1
          end
        end
        
        # Stage 3: Final report
        report = generate_final_report
        
        # Save artifacts
        save_results(report)
        
        {
          success: true,
          report: report,
          run_id: @run_id,
          stats: @artifact_store.stats,
          budget: @budget_tracker.summary
        }
      rescue => e
        @logger&.error("Orchestration error: #{e.message}")
        @logger&.debug(e.backtrace.join("\n")) if @logger
        
        {
          success: false,
          error: e.message,
          run_id: @run_id
        }
      end
    end

    private

    # Generate unique run ID
    def generate_run_id(question)
      timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
      hash = Digest::SHA256.hexdigest(question)[0..7]
      "#{timestamp}_#{hash}"
    end

    # Generate initial research plan
    def generate_initial_plan
      @logger&.info("Generating initial plan...")
      
      prompt_tokens = Budgeting::TokenTracker.estimate_tokens(@config[:question])
      @budget_tracker.record(:planning, prompt_tokens * 2) # Rough estimate
      
      @planner.generate_plan(
        @config[:question],
        model: @config[:models][:reasoning]
      )
    end

    # Execute one round of research
    def execute_research_round
      return unless @plan
      
      @plan.aspects.each do |aspect|
        aspect_id = aspect["id"]
        queries = aspect["queries"] || []
        
        @logger&.info("Researching aspect: #{aspect['title']}")
        
        queries.each do |query|
          # Determine search tool (default to semantic)
          tool = :semantic
          plan = { tool: tool, query: query }
          
          # Execute research
          results = @research_agent.research(
            plan,
            limit: @config[:max_summaries_per_branch] || 6,
            aspect_id: aspect_id,
            model: @config[:models][:summary]
          )
          
          # Store results
          results[:summaries].each do |summary|
            store_artifact("summary", summary.to_h)
          end
          
          # Add facts to collection
          @all_facts.concat(results[:facts])
          
          # Track token usage (rough estimate)
          results[:facts].each do |fact|
            @budget_tracker.record(:summarization, fact.token_count)
          end
          
          # Store facts
          results[:facts].each do |fact|
            store_artifact("fact", fact.to_h)
          end
        end
      end
    end

    # Evaluate current progress
    def evaluate_progress
      @logger&.info("Evaluating progress...")
      
      sources = @artifact_store.unique_sources
      
      evaluation = @evaluator.evaluate(
        @config[:question],
        @plan,
        @all_facts,
        sources,
        model: @config[:models][:fast]
      )
      
      # Track token usage
      @budget_tracker.record(:evaluation, 500) # Rough estimate
      
      evaluation
    end

    # Replan with new gaps
    def replan(missing_aspects)
      @logger&.info("Replanning to address gaps: #{missing_aspects.join(', ')}")
      
      @replans_used += 1
      
      # For now, just continue with existing plan
      # Future: generate delta plan for missing aspects
      @logger&.warn("Replan functionality not fully implemented - continuing with existing plan")
    end

    # Generate final report
    def generate_final_report
      @logger&.info("Generating final report...")
      
      # Rank and select top facts
      top_facts = @ranker.rank(@all_facts, @config[:question], top_k: @config[:relevance_top_k] || 40)
      
      # Compact if needed
      if @compactor.needs_compaction?(top_facts)
        @logger&.info("Compacting facts...")
        top_facts = @compactor.compact(top_facts)
      end
      
      sources = @artifact_store.unique_sources
      
      # Prepare methodology info
      methodology = {
        depth_reached: @current_depth,
        breadth: @plan.aspects.length,
        token_usage: @budget_tracker.usage,
        budget_status: @budget_tracker.exhausted? ? "partial" : "within"
      }
      
      report = @reporter.generate_report(
        @config[:question],
        @plan,
        top_facts,
        sources,
        gaps: [],
        methodology: methodology,
        model: @config[:models][:reasoning]
      )
      
      # Track token usage
      report_tokens = Budgeting::TokenTracker.estimate_tokens(report)
      @budget_tracker.record(:report, report_tokens)
      
      report
    end

    # Store artifact
    def store_artifact(type, data)
      artifact = Models::Artifact.new(type: type, data: data)
      @artifact_store.store(artifact)
    rescue => e
      @logger&.error("Failed to store artifact: #{e.message}")
    end

    # Save final results
    def save_results(report)
      # Save report
      report_path = File.join(@artifact_store.storage_path, "final_report.md")
      File.write(report_path, report)
      @logger&.info("Report saved to: #{report_path}")
      
      # Save manifest
      manifest = {
        question: @config[:question],
        run_id: @run_id,
        plan_version: 2,
        token_usage: @budget_tracker.usage,
        depth_reached: @current_depth,
        aspects_completed: @plan.aspects.length,
        confidence_final: 0.0, # Would come from final evaluation
        sources: @artifact_store.unique_sources.map { |url| { url: url, facts_used: count_facts_for_source(url) } },
        timestamp: Time.now.utc.iso8601
      }
      
      manifest_path = File.join(@artifact_store.storage_path, "manifest.json")
      File.write(manifest_path, JSON.pretty_generate(manifest))
      @logger&.info("Manifest saved to: #{manifest_path}")
    end

    # Count facts for a source
    def count_facts_for_source(url)
      @all_facts.count { |f| f.source_urls.include?(url) }
    end
  end
end
