module GitHubDeepResearchAgent
  # InitialResearchNode - Entry point for GitHub conversation research
  #
  # See lib/github_deep_research_agent.rb for architecture and workflow details.
  #
  # ## Overview
  # This node transforms user research requests into structured semantic searches and
  # enriches results with full conversation data from GitHub. It initializes the workflow
  # memory for all downstream nodes.
  #
  # ## Pipeline Position
  # - Input: User research request and configuration
  # - Output: Enriched conversation dataset with metadata and content
  #
  # @example
  #   node = InitialResearchNode.new
  #   results = node.prep(shared)
  #   enriched = node.exec(results)
  #   node.post(shared, results, enriched)
  class InitialResearchNode < Pocketflow::Node
    # Process user query and execute semantic search.
    #
    # @param shared [Hash] Workflow context with :request, :collection, :top_k, :script_dir
    # @return [Array<Hash>] Search results with URLs, summaries, and scores
    def prep(shared)
      @shared = shared # Store shared context for use in exec() method
      LOG.info "=== INITIAL RESEARCH PHASE ==="
      LOG.info "Starting initial semantic search for: #{shared[:request]}"
      LOG.debug "Collection: #{shared[:collection]}"
      LOG.debug "Max results: #{shared[:top_k]}"

      # Extract configuration parameters from shared context
      request = shared[:request]
      collection = shared[:collection]
      top_k = shared[:top_k]
      script_dir = shared[:script_dir]

      # Extract qualifiers from the user request for targeted semantic search
      # This processes repo:, author:, org: modifiers and builds clean semantic queries
      semantic_query_info = Utils.build_semantic_query(request)
      LOG.debug "Extracted semantic query: '#{semantic_query_info[:semantic_query]}'"
      LOG.debug "Extracted repo filter: #{semantic_query_info[:repo_filter]}" if semantic_query_info[:repo_filter]
      LOG.debug "Extracted author filter: #{semantic_query_info[:author_filter]}" if semantic_query_info[:author_filter]

      # Build comprehensive search plan with extracted qualifiers
      # This combines the original request with processed semantic components
      search_plan = semantic_query_info.merge({ query: request })

      # Construct and execute semantic search command with proper parameter handling
      search_cmd = Utils.build_semantic_search_command(search_plan, script_dir, collection, top_k)
      LOG.debug "Running search command: #{search_cmd}"

      # Execute search and parse results with error handling
      search_output = Utils.run_cmd(search_cmd)
      search_results = JSON.parse(search_output)

      LOG.info "Found #{search_results.length} initial results"

      # Provide detailed search results for debugging and transparency
      LOG.debug do
        result_details = search_results.map.with_index do |result, i|
          "  #{i + 1}. URL: #{result.dig('payload', 'url')}\n" \
          "     Score: #{result['score']}\n" \
          "     Summary: #{result.dig('payload', 'summary')&.slice(0, 100)}..."
        end.join("\n\n")
        "Initial search results:\n#{result_details}"
      end

      search_results
    end

    # Enrich search results with complete conversation data from GitHub.
    #
    # @param search_results [Array<Hash>] Results from prep()
    # @return [Array<Hash>] Enriched conversation objects
    def exec(search_results)
      LOG.info "Fetching detailed conversation data for #{search_results.length} results..."

      # Initialize collection for successfully enriched conversations
      enriched_results = []

      # Process each search result individually with error isolation
      search_results.each_with_index do |result, i|
        url = result.dig("payload", "url")
        next unless url

        LOG.debug "Fetching details for result #{i + 1}/#{search_results.length}: #{url}"

        begin
          # Construct conversation fetch command with cache integration
          fetch_cmd = "#{@shared[:script_dir]}/fetch-github-conversation"
          if @shared[:cache_path]
            fetch_cmd += " --cache-path #{Shellwords.escape(@shared[:cache_path])}"
          end
          fetch_cmd += " #{Shellwords.escape(url)}"

          # Execute fetch command and parse conversation data
          conversation_json = Utils.run_cmd_safe(fetch_cmd)
          conversation_data = JSON.parse(conversation_json)

          # Extract metadata for logging and validation
          metadata = Utils.extract_conversation_metadata(conversation_data)

          LOG.debug do
            "✓ Successfully fetched: #{metadata[:title]}\n" \
            "  Type: #{metadata[:type]}\n" \
            "  State: #{metadata[:state]}\n" \
            "  Comments: #{metadata[:comments_count]}"
          end

          # Assemble enriched conversation object with complete information
          enriched_results << {
            url: url,
            summary: result.dig("payload", "summary") || "",
            score: result["score"],
            conversation: conversation_data
          }
        rescue => e
          # Log individual fetch failures but continue processing other conversations
          LOG.warn "Failed to fetch #{url}: #{e.message}"
        end
      end

      LOG.info "Successfully enriched #{enriched_results.length}/#{search_results.length} conversations"
      enriched_results
    end

    # Initialize workflow memory with enriched research data for downstream nodes.
    #
    # @param shared [Hash] Workflow context to update
    # @param prep_res [Array<Hash>] Search results from prep()
    # @param exec_res [Array<Hash>] Enriched conversations from exec()
    # @return [nil]
    def post(shared, prep_res, exec_res)
      # Initialize workflow memory structure if not already present
      shared[:memory] ||= {}

      # Store enriched conversation data as foundation for all subsequent research
      shared[:memory][:hits] = exec_res

      # Initialize research notes collection for accumulating insights
      shared[:memory][:notes] = []

      # Track initial search query for workflow transparency and iterative research
      shared[:memory][:search_queries] = [shared[:request]]

      LOG.info "✓ Initial research complete: #{exec_res.length} conversations collected"
      LOG.debug "Moving to clarifying questions phase..."

      # Return nil to indicate completion of initialization phase
      nil
    end
  end
end
