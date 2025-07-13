# lib/github_deep_research_agent/initial_research_node.rb
#
# InitialResearchNode: Performs the initial semantic search based on user request.

require_relative "../pocketflow"
require_relative "../utils"

module GitHubDeepResearchAgent
  # InitialResearchNode: Performs the initial semantic search based on user request.
  #
  # This node:
  # - Extracts qualifiers from the user request (repo:, author:, etc.)
  # - Runs semantic search against the Qdrant collection
  # - Fetches detailed conversation data for each result
  # - Initializes the research memory with initial findings
  #
  # This is the first node in the research workflow and sets up the foundation
  # for all subsequent research iterations.
  class InitialResearchNode < Pocketflow::Node
    def prep(shared)
      @shared = shared # Store shared context for use in exec
      LOG.info "=== INITIAL RESEARCH PHASE ==="
      LOG.info "Starting initial semantic search for: #{shared[:request]}"
      LOG.debug "Collection: #{shared[:collection]}"
      LOG.debug "Max results: #{shared[:top_k]}"

      request = shared[:request]
      collection = shared[:collection]
      top_k = shared[:top_k]
      script_dir = shared[:script_dir]

      # Extract qualifiers from the initial request for semantic search
      semantic_query_info = Utils.build_semantic_query(request)
      LOG.debug "Extracted semantic query: '#{semantic_query_info[:semantic_query]}'"
      LOG.debug "Extracted repo filter: #{semantic_query_info[:repo_filter]}" if semantic_query_info[:repo_filter]
      LOG.debug "Extracted author filter: #{semantic_query_info[:author_filter]}" if semantic_query_info[:author_filter]

      # Build search plan with extracted qualifiers
      search_plan = semantic_query_info.merge({ query: request })

      # Run semantic search with qualifier extraction
      search_cmd = Utils.build_semantic_search_command(search_plan, script_dir, collection, top_k)
      LOG.debug "Running search command: #{search_cmd}"

      search_output = Utils.run_cmd(search_cmd)
      search_results = JSON.parse(search_output)

      LOG.info "Found #{search_results.length} initial results"
      # LOG.debug example: showing detailed search results when verbose logging is enabled
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

    def exec(search_results)
      LOG.info "Fetching detailed conversation data for #{search_results.length} results..."

      # Fetch detailed conversation data for each result
      enriched_results = []

      search_results.each_with_index do |result, i|
        url = result.dig("payload", "url")
        next unless url

        LOG.debug "Fetching details for result #{i + 1}/#{search_results.length}: #{url}"

        begin
          fetch_cmd = "#{@shared[:script_dir]}/fetch-github-conversation"
          if @shared[:cache_path]
            fetch_cmd += " --cache-path #{Shellwords.escape(@shared[:cache_path])}"
          end
          fetch_cmd += " #{Shellwords.escape(url)}"

          conversation_json = Utils.run_cmd_safe(fetch_cmd)
          conversation_data = JSON.parse(conversation_json)

          metadata = Utils.extract_conversation_metadata(conversation_data)

          LOG.debug do
            "✓ Successfully fetched: #{metadata[:title]}\n" \
            "  Type: #{metadata[:type]}\n" \
            "  State: #{metadata[:state]}\n" \
            "  Comments: #{metadata[:comments_count]}"
          end

          enriched_results << {
            url: url,
            summary: result.dig("payload", "summary") || "",
            score: result["score"],
            conversation: conversation_data
          }
        rescue => e
          LOG.warn "Failed to fetch #{url}: #{e.message}"
        end
      end

      LOG.info "Successfully enriched #{enriched_results.length}/#{search_results.length} conversations"
      enriched_results
    end

    def post(shared, prep_res, exec_res)
      shared[:memory] ||= {}
      shared[:memory][:hits] = exec_res
      shared[:memory][:notes] = []
      shared[:memory][:search_queries] = [shared[:request]]

      LOG.info "✓ Initial research complete: #{exec_res.length} conversations collected"
      LOG.debug "Moving to clarifying questions phase..."

      nil
    end
  end
end
