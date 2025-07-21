module GitHubDeepResearchAgent
  # ParallelRetrieverNode - Concurrent search execution and data enrichment
  #
  # This node extends the base RetrieverNode to execute multiple search plans
  # concurrently using Pocketflow's ParallelBatchNode capabilities. This provides
  # significant performance improvements when running multiple search modes
  # (semantic + keyword) or processing large result sets.
  #
  # ## Parallelization Benefits
  # - **Search Execution**: Semantic and keyword searches run concurrently
  # - **Conversation Fetching**: GitHub API calls executed in parallel threads
  # - **Summary Generation**: LLM calls for missing summaries run concurrently
  # - **Result Processing**: Deduplication and enrichment happen in parallel
  #
  # ## Thread Safety
  # - Each thread gets isolated copies of conversation data
  # - Results are merged safely back to main context
  # - Error handling preserves individual operation failures
  #
  # @example
  #   # Drop-in replacement for RetrieverNode
  #   retriever_node = GitHubDeepResearchAgent::ParallelRetrieverNode.new(logger: logger)
  #   planner_node.next(retriever_node)
  class ParallelRetrieverNode < Pocketflow::ParallelBatchNode
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Validate search plans and prepare for parallel execution.
    #
    # @param shared [Hash] Workflow context with :next_search_plans, :collection, :top_k, :script_dir
    # @return [Array<Hash>, nil] Valid search plans or nil
    def prep(shared)
      @shared = shared # Store shared context for access in exec() and post()
      search_plans = shared[:next_search_plans]

      # Validate that PlannerNode provided search plans
      if search_plans.nil? || search_plans.empty?
        logger.info "No search plans found from PlannerNode"
        return nil
      end

      # Announce parallel retrieval phase
      logger.info "=== PARALLEL RETRIEVAL PHASE ==="
      logger.info "Executing #{search_plans.length} search operations concurrently:"
      search_plans.each_with_index do |plan, i|
        logger.info "  #{i + 1}. #{plan[:tool]} search with query: \"#{plan[:query]}\""
      end

      search_plans
    end

    # Execute a single search plan concurrently (called per thread).
    #
    # @param search_plan [Hash] Individual search plan with tool, query, etc.
    # @return [Hash] Search results with metadata
    def exec(search_plan)
      # Extract search configuration from shared context
      collection = @shared[:collection]
      top_k = @shared[:top_k]
      script_dir = @shared[:script_dir]

      tool = search_plan[:tool]
      logger.info "[Thread] Executing #{tool} search: \"#{search_plan[:query]}\""

      begin
        # Execute the search plan
        search_results = execute_single_search(search_plan, script_dir, collection, top_k)

        logger.info "[Thread] #{tool} search completed: #{search_results.length} results"

        # Return results with thread identifier
        {
          tool: tool,
          query: search_plan[:query],
          results: search_results,
          thread_id: Thread.current.object_id
        }
      rescue => e
        logger.warn "[Thread] #{tool} search failed: #{e.message}"
        {
          tool: tool,
          query: search_plan[:query],
          results: [],
          error: e.message,
          thread_id: Thread.current.object_id
        }
      end
    end

    # Aggregate parallel search results and enrich conversations.
    #
    # @param shared [Hash] Workflow context to update
    # @param prep_res [Array<Hash>] Search plans from prep()
    # @param exec_res [Array<Hash>] Parallel search results from exec()
    # @return [String] "continue" or "final"
    def post(shared, prep_res, exec_res)
      return "final" if prep_res.nil? || prep_res.empty?

      logger.info "=== AGGREGATING PARALLEL RESULTS ==="

      # Combine results from all parallel searches
      all_results = []
      url_to_result = {} # For deduplication across search modes

      exec_res.each do |thread_result|
        next if thread_result[:error] # Skip failed searches

        tool = thread_result[:tool]
        search_results = thread_result[:results]

        logger.info "Processing #{search_results.length} results from #{tool} search"

        # Deduplicate and merge results, preserving highest relevance scores
        search_results.each do |result|
          url = result.dig("payload", "url")
          next unless url

          # Keep the result with higher score, or semantic over keyword if scores are equal
          existing = url_to_result[url]
          if !existing ||
             result["score"] > existing["score"] ||
             (result["score"] == existing["score"] && tool == :semantic)
            url_to_result[url] = result.merge("search_mode" => tool.to_s)
          end
        end
      end

      # Convert deduplicated results back to array, limited by top_k
      combined_results = url_to_result.values.first(shared[:top_k])
      logger.info "Combined parallel results: #{combined_results.length} unique conversations"

      # Deduplicate against existing conversations in research memory
      existing_urls = shared[:memory][:hits].map { |hit| hit[:url] }.to_set
      new_results = combined_results.reject { |result| existing_urls.include?(result.dig("payload", "url")) }

      logger.info "Found #{new_results.length} new conversations after deduplication"

      # Handle case where all search results are duplicates
      if new_results.empty?
        logger.info "No new results found - all were duplicates"
        return route_to_next_phase(shared, [])
      end

      # Parallel conversation enrichment
      logger.info "Enriching #{new_results.length} conversations in parallel..."
      enriched_conversations = enrich_conversations_parallel(new_results, shared)

      logger.info "Successfully enriched #{enriched_conversations.length}/#{new_results.length} conversations"

      route_to_next_phase(shared, enriched_conversations)
    end

    private

    # Enrich conversations with detailed data and summaries using parallel processing.
    #
    # @param new_results [Array<Hash>] Search results to enrich
    # @param shared [Hash] Shared context with configuration
    # @return [Array<Hash>] Enriched conversation data
    def enrich_conversations_parallel(new_results, shared)
      # Create a parallel batch processor for conversation enrichment
      enrichment_processor = ConversationEnrichmentProcessor.new(logger: logger)

      # Prepare batch parameters for each conversation
      conversation_batches = new_results.map.with_index do |result, i|
        {
          result: result,
          index: i,
          total: new_results.length,
          cache_path: shared[:cache_path],
          script_dir: shared[:script_dir],
          collection: shared[:collection]
        }
      end

      # Execute parallel enrichment
      enriched_results = []

      conversation_batches.each do |batch|
        enriched = enrichment_processor.exec(batch)
        enriched_results << enriched if enriched
      end

      enriched_results.compact
    end

    # Route to next workflow phase based on research state.
    #
    # @param shared [Hash] Workflow context
    # @param enriched_results [Array<Hash>] Enriched conversation data
    # @return [String] Routing decision
    def route_to_next_phase(shared, enriched_results)
      # Extract query information for memory tracking
      queries = (shared[:next_search_plans] || []).map { |plan| "#{plan[:tool]}: #{plan[:query]}" }
      query_summary = queries.join("; ")

      # Integrate new findings into research memory
      shared[:memory][:hits].concat(enriched_results)
      shared[:memory][:search_queries] << query_summary

      # Generate research notes for this iteration
      if enriched_results.any?
        notes = enriched_results.map { |hit| "#{hit[:url]} (via #{hit[:search_mode]}): #{hit[:summary]}" }.join("\n")
        shared[:memory][:notes] << "Research iteration: #{notes}"
        logger.info "Added #{enriched_results.length} new conversations to memory"
      else
        logger.info "No new conversations added this iteration"
      end

      # Increment research iteration depth counter
      shared[:current_depth] = (shared[:current_depth] || 0) + 1

      # Determine workflow continuation
      if shared[:current_depth] < shared[:max_depth] && enriched_results.any?
        logger.info "Continuing to next research iteration..."
        "continue"
      else
        logger.info "Research complete, moving to final report..."

        # Clear unsupported claims after research completion
        if shared[:unsupported_claims] && shared[:unsupported_claims].any?
          logger.info "Clearing unsupported claims after research attempt"
          shared[:unsupported_claims] = []
        end

        "final"
      end
    end

    # Execute a single search plan and return normalized results.
    # (Same implementation as RetrieverNode for consistency)
    def execute_single_search(search_plan, script_dir, collection, top_k)
      tool = search_plan[:tool]
      query = search_plan[:query]

      case tool
      when :semantic
        # Build semantic search command
        semantic_query_info = build_semantic_query(query)
        updated_search_plan = search_plan.merge(semantic_query_info)
        search_cmd = build_semantic_search_command(updated_search_plan, script_dir, collection, top_k)

        search_output = Utils.run_cmd(search_cmd)
        JSON.parse(search_output)

      when :keyword
        search_cmd = "#{script_dir}/search-github-conversations #{Shellwords.escape(query)}"
        search_output = Utils.run_cmd(search_cmd)
        keyword_results = JSON.parse(search_output)

        # Normalize keyword search results
        keyword_results.map do |result|
          {
            "payload" => {
              "url" => result["url"],
              "summary" => ""
            },
            "score" => 0.0
          }
        end.first(top_k)

      else
        logger.warn "Unknown search tool: #{tool}, skipping"
        []
      end
    end

    # Build semantic search command with all parameters.
    def build_semantic_search_command(search_plan, script_dir, collection, top_k)
      cmd = "#{script_dir}/semantic-search-github-conversations"
      cmd += " #{Shellwords.escape(search_plan[:semantic_query] || search_plan[:query])}"
      cmd += " --collection #{Shellwords.escape(collection)}"
      cmd += " --limit #{top_k}"
      cmd += " --format json"

      # Add temporal filters
      if search_plan[:created_after]
        cmd += " --filter created_after:#{Shellwords.escape(search_plan[:created_after])}"
      end
      if search_plan[:created_before]
        cmd += " --filter created_before:#{Shellwords.escape(search_plan[:created_before])}"
      end

      cmd
    end

    # Extract semantic query information.
    def build_semantic_query(query)
      # Simple implementation - could be enhanced with temporal parsing
      { semantic_query: query }
    end
  end

  # ConversationEnrichmentProcessor - Handles individual conversation enrichment
  #
  # This processor handles the enrichment of individual GitHub conversations
  # with detailed conversation data and AI-generated summaries. Designed for
  # use with parallel processing frameworks.
  class ConversationEnrichmentProcessor < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Enrich a single conversation with detailed data and summary.
    #
    # @param batch [Hash] Batch parameters with result, index, configuration
    # @return [Hash, nil] Enriched conversation or nil on failure
    def exec(batch)
      result = batch[:result]
      index = batch[:index]
      total = batch[:total]
      cache_path = batch[:cache_path]
      script_dir = batch[:script_dir]
      collection = batch[:collection]

      url = result.dig("payload", "url")
      return nil unless url

      thread_id = Thread.current.object_id
      logger.info "[Thread #{thread_id}] Fetching #{index + 1}/#{total}: #{url}"

      begin
        # Build conversation fetching command
        fetch_cmd = "#{script_dir}/fetch-github-conversation"
        if cache_path
          fetch_cmd += " --cache-path #{Shellwords.escape(cache_path)}"
        end
        fetch_cmd += " #{Shellwords.escape(url)}"

        # Execute conversation fetch
        conversation_json = Utils.run_cmd_safe(fetch_cmd)
        conversation_data = JSON.parse(conversation_json)

        # Get or generate summary
        summary = result.dig("payload", "summary") || ""
        if summary.empty?
          summary = generate_summary_if_missing(url, collection, script_dir, cache_path)
        end

        # Return enriched conversation data
        {
          url: url,
          summary: summary,
          score: result["score"],
          search_mode: result["search_mode"],
          conversation: conversation_data
        }
      rescue => e
        logger.warn "[Thread #{thread_id}] Failed to enrich #{url}: #{e.message}"
        nil
      end
    end

    private

    # Generate summary if missing from search results.
    def generate_summary_if_missing(url, collection, script_dir, cache_path)
      begin
        # Try to find existing summary in Qdrant first
        search_cmd = "#{script_dir}/semantic-search-github-conversations"
        search_cmd += " #{Shellwords.escape(url)}"
        search_cmd += " --collection #{Shellwords.escape(collection)}"
        search_cmd += " --limit 1"

        search_output = Utils.run_cmd(search_cmd)
        search_results = JSON.parse(search_output)

        if search_results.any? && search_results.first.dig("payload", "summary")
          summary = search_results.first.dig("payload", "summary")
          return summary unless summary.empty?
        end

        # Generate new summary if none found
        fetch_cmd = "#{script_dir}/fetch-github-conversation"
        if cache_path
          fetch_cmd += " --cache-path #{Shellwords.escape(cache_path)}"
        end
        fetch_cmd += " #{Shellwords.escape(url)}"

        conversation_json = Utils.run_cmd(fetch_cmd)
        conversation_data = JSON.parse(conversation_json)

        # Generate summary using LLM
        summary_prompt = Utils.fill_template(EXECUTIVE_SUMMARY_PROMPT, {
          conversation: conversation_data.to_json
        })

        Utils.call_llm(summary_prompt, :fast)
      rescue => e
        logger.warn "Failed to generate summary for #{url}: #{e.message}"
        url # Fallback to URL
      end
    end

    # Executive summary prompt template
    EXECUTIVE_SUMMARY_PROMPT = <<~PROMPT
      # Executive summary instructions
      I need help summarizing a conversation from GitHub. Here are the rules I need you to follow:

      1. Concise, Informative Title: Begin with a clear, succinct title that encapsulates the main subject or decision at hand.
      2. Narrative-Driven Summary: Present the summary as a series of well-structured paragraphs. Avoid bullets, headers, or lists. Use a formal, professional tone.
      3. Complete Contextual Linking: Provide direct links to referenced comments, events, or resources.
      4. Focus on Critical Content: Include only details that significantly influenced direction, decisions, or outcomes.
      5. Alternatives and Next Steps: Explain explored alternatives and future plans with links to source comments.
      6. Formal Tone, Dense Prose: Maintain authoritative tone with complete sentences.

      Conversation to summarize:
      {{conversation}}
    PROMPT
  end
end
