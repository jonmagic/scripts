module GitHubDeepResearchAgent
  # ParallelResearchFlow - Concurrent multi-question research pipeline
  #
  # This flow extends the base research workflow to handle multiple research questions
  # or research contexts concurrently using Pocketflow's ParallelBatchFlow capabilities.
  # Perfect for comparative analysis or batch research operations.
  #
  # ## Use Cases
  # - **Comparative Research**: Research multiple related topics simultaneously
  # - **Multi-Repository Analysis**: Study the same question across different repos
  # - **Historical Analysis**: Research the same topic across different time periods
  # - **Batch Operations**: Process multiple research requests from a queue
  #
  # ## Parallelization Benefits
  # - **Independent Research**: Each question gets its own research context
  # - **Resource Utilization**: Multiple LLM and search operations run concurrently
  # - **Throughput**: Significant speed improvement for batch operations
  # - **Isolation**: Research contexts don't interfere with each other
  #
  # @example
  #   questions = [
  #     "How does rate limiting work in the GitHub API?",
  #     "What are the authentication methods for GitHub Apps?",
  #     "How does GitHub handle webhook delivery failures?"
  #   ]
  #
  #   flow = GitHubDeepResearchAgent::ParallelResearchFlow.start_batch(
  #     questions: questions,
  #     collection: "github-conversations",
  #     cache_path: "data"
  #   )
  class ParallelResearchFlow < Pocketflow::ParallelBatchFlow
    attr_accessor :logger

    def initialize(start_node, logger: Log.logger, **kwargs)
      super(start_node, **kwargs)
      @logger = logger
    end

    # Prepare batch research parameters from multiple questions.
    #
    # @param shared [Hash] Workflow context with :research_questions, :base_options
    # @return [Array<Hash>] Batch parameters for each research question
    def prep(shared)
      research_questions = shared[:research_questions] || []
      base_options = shared[:base_options] || {}

      if research_questions.empty?
        logger.warn "No research questions provided for parallel processing"
        return []
      end

      logger.info "=== PARALLEL RESEARCH FLOW ==="
      logger.info "Preparing #{research_questions.length} research questions for concurrent processing"

      # Create batch parameters for each research question
      batch_params = research_questions.map.with_index do |question, i|
        question_id = "question_#{i + 1}"

        logger.info "#{question_id}: #{question}"

        # Create isolated research context for each question
        {
          question_id: question_id,
          request: question,
          collection: base_options[:collection],
          top_k: base_options[:limit] || 5,
          max_depth: base_options[:max_depth] || 2,
          cache_path: base_options[:cache_path],
          script_dir: base_options[:script_dir],
          search_modes: base_options[:search_modes] || ["semantic", "keyword"],
          models: base_options[:models] || {},
          # Initialize isolated memory for each research thread
          memory: {
            hits: [],
            search_queries: [],
            notes: []
          },
          current_depth: 0
        }
      end

      batch_params
    end

    # Aggregate results from all parallel research threads.
    #
    # @param shared [Hash] Main workflow context
    # @param prep_res [Array<Hash>] Batch parameters from prep()
    # @param exec_res [nil] Not used in ParallelBatchFlow
    # @return [nil] Always nil for flows
    def post(shared, prep_res, exec_res)
      logger.info "=== PARALLEL RESEARCH COMPLETE ==="

      if prep_res.empty?
        logger.info "No research questions were processed"
        return nil
      end

      # Collect aggregated results from all research threads
      all_results = shared[:research_results] || {}

      logger.info "Research Summary:"
      logger.info "=================="

      total_conversations = 0
      total_iterations = 0

      prep_res.each do |batch_param|
        question_id = batch_param[:question_id]
        question = batch_param[:request]
        result = all_results[question_id]

        if result
          conversations_count = result[:memory][:hits].length
          iterations_count = result[:current_depth] || 0

          total_conversations += conversations_count
          total_iterations += iterations_count

          logger.info "#{question_id}: #{conversations_count} conversations, #{iterations_count} iterations"
          logger.info "  Question: #{question}"

          if result[:final_report]
            logger.info "  Status: Completed with final report"
          else
            logger.info "  Status: Completed without final report"
          end
        else
          logger.warn "#{question_id}: No results found"
          logger.info "  Question: #{question}"
        end
      end

      logger.info "=================="
      logger.info "Total: #{total_conversations} conversations across #{prep_res.length} questions"
      logger.info "Average: #{total_iterations / prep_res.length.to_f} iterations per question"

      nil # Flows always return nil from post
    end

    # Class method to start parallel research with multiple questions.
    #
    # @param questions [Array<String>] Research questions to process
    # @param options [Hash] Base configuration options
    # @return [Hash] Aggregated research results
    def self.start_batch(questions:, **options)
      logger = options[:logger] || Log.logger

      # Set up shared context for batch processing
      shared = {
        research_questions: questions,
        base_options: options,
        research_results: {}
      }

      # Build the parallel research workflow
      initial_node = GitHubDeepResearchAgent::InitialResearchNode.new(logger: logger)
      clarify_node = GitHubDeepResearchAgent::AskClarifyingNode.new(logger: logger)
      planner_node = GitHubDeepResearchAgent::PlannerNode.new(logger: logger)

      # Use parallel retriever for better performance
      retriever_node = GitHubDeepResearchAgent::ParallelRetrieverNode.new(logger: logger)

      compaction_node = GitHubDeepResearchAgent::ContextCompactionNode.new(logger: logger)

      # Use parallel claim verifier for better performance
      claim_verifier_node = GitHubDeepResearchAgent::ParallelClaimVerifierNode.new(logger: logger)

      final_node = GitHubDeepResearchAgent::FinalReportNode.new(logger: logger)
      end_node = GitHubDeepResearchAgent::EndNode.new(logger: logger)

      # Link the nodes for each individual research workflow
      initial_node.next(clarify_node)
      clarify_node.next(planner_node)
      planner_node.next(retriever_node)
      retriever_node.on("continue", planner_node)
      retriever_node.on("final", final_node)

      # Add claim verification flow
      final_node.on("verify", claim_verifier_node)
      final_node.on("complete", end_node)
      claim_verifier_node.on("ok", final_node)
      claim_verifier_node.on("fix", planner_node)

      # Add compaction handling
      final_node.on("compact", compaction_node)
      compaction_node.on("retry", final_node)
      compaction_node.on("proceed_anyway", final_node)
      final_node.next(end_node)

      # Create and run the parallel batch flow
      parallel_flow = new(initial_node, logger: logger)

      logger.info "Starting parallel research for #{questions.length} questions"
      parallel_flow.run(shared)

      # Return aggregated results
      shared[:research_results]
    end

    # Class method for comparative research across repositories.
    #
    # @param question [String] The research question to ask about each repo
    # @param repos [Array<String>] Repository identifiers (owner/repo)
    # @param options [Hash] Base configuration options
    # @return [Hash] Comparative research results
    def self.comparative_research(question:, repos:, **options)
      # Transform repositories into research questions
      questions = repos.map do |repo|
        "#{question} (in repository #{repo})"
      end

      # Add repository filters to search modes
      enhanced_options = options.dup
      enhanced_options[:search_modes] = ["semantic"] # Focus on semantic for repo-specific research

      start_batch(questions: questions, **enhanced_options)
    end

    # Class method for temporal research analysis.
    #
    # @param question [String] The base research question
    # @param time_periods [Array<Hash>] Time period configurations with :after, :before, :label
    # @param options [Hash] Base configuration options
    # @return [Hash] Temporal research results
    def self.temporal_research(question:, time_periods:, **options)
      # Transform time periods into research questions
      questions = time_periods.map do |period|
        period_label = period[:label] || "#{period[:after]} to #{period[:before]}"
        "#{question} (during #{period_label})"
      end

      start_batch(questions: questions, **options)
    end
  end

  # ParallelResearchAggregator - Aggregates results from parallel research threads
  #
  # This node aggregates and stores results from multiple parallel research operations.
  # It runs after all parallel research threads complete and compiles their findings.
  class ParallelResearchAggregator < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Collect and organize results from all research threads.
    #
    # @param shared [Hash] Workflow context with research results from all threads
    # @return [Hash] Organization metadata
    def prep(shared)
      @shared = shared
      logger.info "=== AGGREGATING PARALLEL RESEARCH RESULTS ==="

      research_results = shared[:research_results] || {}

      {
        total_questions: research_results.keys.length,
        total_conversations: research_results.values.sum { |r| r[:memory][:hits].length rescue 0 }
      }
    end

    # Process and format aggregated results.
    #
    # @param metadata [Hash] Metadata from prep()
    # @return [String] Formatted summary
    def exec(metadata)
      research_results = @shared[:research_results] || {}

      summary_parts = []
      summary_parts << "# Parallel Research Summary\n"
      summary_parts << "Processed #{metadata[:total_questions]} research questions"
      summary_parts << "Total conversations analyzed: #{metadata[:total_conversations]}\n"

      research_results.each do |question_id, result|
        summary_parts << "## #{question_id.humanize}"
        summary_parts << "**Question**: #{result[:request]}"
        summary_parts << "**Conversations**: #{result[:memory][:hits].length}"
        summary_parts << "**Search Queries**: #{result[:memory][:search_queries].join(', ')}"

        if result[:final_report]
          summary_parts << "**Status**: Completed\n"
          summary_parts << result[:final_report]
        else
          summary_parts << "**Status**: Incomplete"
        end

        summary_parts << "\n---\n"
      end

      summary_parts.join("\n")
    end

    # Output aggregated results and complete workflow.
    #
    # @param shared [Hash] Workflow context
    # @param prep_res [Hash] Metadata from prep()
    # @param exec_res [String] Summary from exec()
    # @return [nil]
    def post(shared, prep_res, exec_res)
      puts exec_res
      logger.info "✓ Parallel research aggregation complete!"
      nil
    end
  end
end
