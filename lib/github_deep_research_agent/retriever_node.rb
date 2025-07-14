module GitHubDeepResearchAgent
  # RetrieverNode - Executes search operations and processes results
  #
  # See lib/github_deep_research_agent.rb for architecture and workflow details.
  #
  # ## Overview
  # This node executes structured search plans (semantic, keyword, or hybrid), fetches and enriches
  # GitHub conversations, and updates research memory for downstream analysis and reporting.
  #
  # ## Pipeline Position
  # - Input: Structured search plans from PlannerNode
  # - Output: Enhanced conversation data for analysis and reporting
  #
  # @example
  #   node = RetrieverNode.new
  #   plan = node.prep(shared)
  #   results = node.exec(plan)
  #   node.post(shared, plan, results)
  class RetrieverNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end
    # Validate search plans and initialize search execution.
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

      # Announce retrieval phase and preview search operations
      logger.info "=== RETRIEVAL PHASE ==="
      logger.info "Executing #{search_plans.length} search operations:"
      search_plans.each_with_index do |plan, i|
        logger.info "  #{i + 1}. #{plan[:tool]} search with query: \"#{plan[:query]}\""
      end

      search_plans
    end

    # Execute search operations and retrieve conversation data.
    #
    # @param search_plans [Array<Hash>] Search plans with tool, query, etc.
    # @return [Array<Hash>] Enhanced conversation results
    def exec(search_plans)
      return [] if search_plans.nil? || search_plans.empty?

      # Extract search configuration from shared context
      collection = @shared[:collection]
      top_k = @shared[:top_k]
      script_dir = @shared[:script_dir]

      all_results = []
      url_to_result = {} # For deduplication across search modes

      # Execute each search plan separately
      search_plans.each_with_index do |search_plan, plan_index|
        tool = search_plan[:tool]
        logger.info "Executing search plan #{plan_index + 1}/#{search_plans.length}: #{tool} search"

        search_results = execute_single_search(search_plan, script_dir, collection, top_k)

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
      combined_results = url_to_result.values.first(top_k)
      logger.info "Combined results from #{search_plans.length} search modes into #{combined_results.length} unique conversations"

      # Deduplicate against existing conversations in research memory
      # Prevent re-processing conversations already analyzed in previous iterations
      existing_urls = @shared[:memory][:hits].map { |hit| hit[:url] }.to_set
      new_results = combined_results.reject { |result| existing_urls.include?(result.dig("payload", "url")) }

      logger.info "Found #{new_results.length} new conversations after deduplication"

      # Handle case where all search results are duplicates of previous iterations
      if new_results.empty?
        logger.info "No new results found - all were duplicates"
        return []
      end

      # Fetch detailed conversation data for all new results
      # This enriches the basic search results with full conversation content
      new_enriched = []
      new_results.each_with_index do |result, i|
        url = result.dig("payload", "url")
        next unless url

        logger.info "Fetching details for new result #{i + 1}/#{new_results.length}: #{url}"

        begin
          # Build conversation fetching command with optional caching
          fetch_cmd = "#{@shared[:script_dir]}/fetch-github-conversation"
          if @shared[:cache_path]
            fetch_cmd += " --cache-path #{Shellwords.escape(@shared[:cache_path])}"
          end
          fetch_cmd += " #{Shellwords.escape(url)}"

          # Execute conversation fetch and parse JSON response
          conversation_json = Utils.run_cmd_safe(fetch_cmd)
          conversation_data = JSON.parse(conversation_json)

          # Extract metadata for additional conversation context
          metadata = extract_conversation_metadata(conversation_data)

          # Store enriched conversation data with all components
          new_enriched << {
            url: url,
            summary: result.dig("payload", "summary") || "",
            score: result["score"],
            search_mode: result["search_mode"],
            conversation: conversation_data
          }
        rescue => e
          logger.warn "Failed to fetch #{url}: #{e.message}"
        end
      end

      logger.info "Successfully enriched #{new_enriched.length}/#{new_results.length} new conversations"

      # Enrich any conversations that still have empty summaries
      # This handles search results that don't have summaries initially
      new_enriched.each do |enriched_result|
        url = enriched_result[:url]
        next unless url

        # Skip if already has a summary
        next if enriched_result[:summary] && !enriched_result[:summary].empty?

        # Get or generate summary for conversations missing summaries
        # This ensures all conversations have summaries for analysis
        summary = get_or_generate_summary(
          url,
          @shared[:collection],
          @shared[:script_dir],
          @shared[:cache_path]
        )

        # Update enriched result with generated summary
        enriched_result[:summary] = summary
      end

      # Return enriched conversation data for downstream processing
      new_enriched
    end

    # Update research memory and coordinate workflow routing after retrieval.
    #
    # @param shared [Hash] Workflow context to update
    # @param prep_res [Array<Hash>] Search plans from prep()
    # @param exec_res [Array<Hash>] Enriched conversation results from exec()
    # @return [String] "continue" or "final"
    def post(shared, prep_res, exec_res)
      return "final" if prep_res.nil? || prep_res.empty? # No search plans available

      # Extract query information for memory tracking and research notes
      # Create a summary of all search queries executed
      queries = prep_res.map { |plan| "#{plan[:tool]}: #{plan[:query]}" }
      query_summary = queries.join("; ")

      # Integrate new findings into comprehensive research memory
      shared[:memory][:hits].concat(exec_res)
      shared[:memory][:search_queries] << query_summary

      # Generate research notes for this iteration
      if exec_res.any?
        # Create human-readable summary of iteration findings
        notes = exec_res.map { |hit| "#{hit[:url]} (via #{hit[:search_mode]}): #{hit[:summary]}" }.join("\n")
        shared[:memory][:notes] << "Research iteration: #{notes}"
        logger.info "Added #{exec_res.length} new conversations to memory"
      else
        logger.info "No new conversations added this iteration"
      end

      # Increment research iteration depth counter
      shared[:current_depth] = (shared[:current_depth] || 0) + 1

      # Determine workflow continuation based on depth and result quality
      if shared[:current_depth] < shared[:max_depth] && exec_res.any?
        logger.info "Continuing to next research iteration..."
        "continue" # Return to PlannerNode for next research iteration
      else
        logger.info "Research complete, moving to final report..."

        # Clear unsupported claims after research completion
        # Prevents re-triggering claim verification loops in subsequent workflow runs
        if shared[:unsupported_claims] && shared[:unsupported_claims].any?
          logger.info "Clearing unsupported claims after research attempt"
          shared[:unsupported_claims] = []
        end

        "final" # Route to FinalReportNode for comprehensive report generation
      end
    end

    private

    # Constructs semantic search command with all parameters and constraints
    #
    # This helper method builds the complete command line for executing semantic
    # searches against the Qdrant vector database. It handles all search parameters
    # including temporal constraints, result limits, and ordering preferences.
    #
    # ## Command Construction
    # Builds comprehensive semantic search commands:
    # - **Base Command**: Uses semantic-search-github-conversations script
    # - **Query Parameter**: Properly escaped search query for vector similarity
    # - **Collection Parameter**: Specifies target Qdrant collection
    # - **Result Limiting**: Applies top_k limit for result count
    # - **Temporal Constraints**: Adds optional date filtering parameters
    # - **Ordering Options**: Specifies result ordering preferences when provided
    #
    # ## Parameter Handling
    # Manages optional and required search parameters:
    # - **Required Parameters**: Query, script_dir, collection, top_k always included
    # - **Optional Temporal**: created_after and created_before when specified
    # - **Optional Ordering**: order_by parameter when ordering preference exists
    # - **Shell Escaping**: Proper escaping of all user-provided strings
    #
    # @param search_plan [Hash] Search plan containing:
    #   - :query => String Search query for vector similarity matching
    #   - :created_after => String Optional ISO date for temporal filtering
    #   - :created_before => String Optional ISO date for temporal filtering
    #   - :order_by => String Optional result ordering preference
    # @param script_dir [String] Directory containing semantic search executable
    # @param collection [String] Target Qdrant collection name
    # @param top_k [Integer] Maximum number of results to retrieve
    # @return [String] Complete shell command ready for execution
    def build_semantic_search_command(search_plan, script_dir, collection, top_k)
      # Build base semantic search command with required parameters
      cmd = "#{script_dir}/semantic-search-github-conversations"
      cmd += " #{Shellwords.escape(search_plan[:query])}"
      cmd += " --collection #{Shellwords.escape(collection)}"
      cmd += " --limit #{top_k}"
      cmd += " --format json"

      # Add temporal filters for date-based constraints
      if search_plan[:created_after]
        cmd += " --filter created_after:#{Shellwords.escape(search_plan[:created_after])}"
      end
      if search_plan[:created_before]
        cmd += " --filter created_before:#{Shellwords.escape(search_plan[:created_before])}"
      end

      # Add ordering specification with key and direction
      if search_plan[:order_by]
        order_by_str = "#{search_plan[:order_by][:key]} #{search_plan[:order_by][:direction]}"
        cmd += " --order-by #{Shellwords.escape(order_by_str)}"
      end

      cmd
    end

    # Extracts and processes semantic query information for vector search
    #
    # This helper method processes search queries to extract semantic search
    # components and temporal constraints. It prepares queries for optimal
    # vector similarity matching in the Qdrant database.
    #
    # ## Query Processing
    # Performs intelligent query analysis and preparation:
    # - **Semantic Extraction**: Identifies core concepts for vector similarity
    # - **Temporal Parsing**: Extracts date constraints from natural language
    # - **Keyword Filtering**: Removes search operators that don't apply to semantic search
    # - **Query Optimization**: Prepares queries for optimal vector matching
    #
    # ## Output Format
    # Returns structured query information:
    # - **semantic_query**: Processed query optimized for vector similarity
    # - **created_after**: Extracted start date constraint (if present)
    # - **created_before**: Extracted end date constraint (if present)
    # - **order_by**: Extracted ordering preference (if present)
    #
    # @param query [String] Raw search query potentially containing temporal constraints
    # @return [Hash] Processed query information with:
    #   - :semantic_query => String Query optimized for semantic search
    #   - :created_after => String Optional ISO date constraint
    #   - :created_before => String Optional ISO date constraint
    #   - :order_by => String Optional result ordering preference
    def build_semantic_query(query)
      # For now, return the query as-is for semantic search
      # Future enhancement: could parse temporal qualifiers from natural language
      {
        semantic_query: query
      }
    end

    # Retrieves or generates conversation summaries using multiple strategies
    #
    # This helper method implements a comprehensive strategy for obtaining
    # conversation summaries, trying multiple approaches to ensure all
    # conversations have meaningful summaries for analysis.
    #
    # ## Summary Retrieval Strategy
    # Implements fallback strategy for summary acquisition:
    # - **Primary**: Attempt to retrieve existing summary from Qdrant collection
    # - **Secondary**: Generate new summary using LLM if no existing summary found
    # - **Fallback**: Return URL as identifier if all summary generation fails
    # - **Caching**: Utilizes conversation caching to minimize redundant processing
    #
    # ## Qdrant Integration
    # Queries vector database for existing summaries:
    # - **Exact URL Matching**: Searches for conversations with matching URLs
    # - **Summary Extraction**: Retrieves pre-generated summaries from payload data
    # - **Metadata Validation**: Ensures retrieved summaries are meaningful and current
    #
    # ## LLM Summary Generation
    # Generates new summaries when needed:
    # - **Conversation Fetching**: Retrieves full conversation data via GitHub API
    # - **Content Processing**: Prepares conversation content for summarization
    # - **Template Processing**: Uses structured prompts for consistent summary quality
    # - **Error Handling**: Graceful degradation when summarization fails
    #
    # @param url [String] GitHub conversation URL to summarize
    # @param collection [String] Qdrant collection to search for existing summaries
    # @param script_dir [String] Directory containing conversation fetching scripts
    # @param cache_path [String] Optional cache directory for conversation data
    # @return [String] Conversation summary or URL if summary generation fails
    def get_or_generate_summary(url, collection, script_dir, cache_path)
      # Try to find existing summary in Qdrant first
      search_cmd = "#{script_dir}/semantic-search-github-conversations"
      search_cmd += " #{Shellwords.escape(url)}"
      search_cmd += " --collection #{Shellwords.escape(collection)}"
      search_cmd += " --limit 1"

      begin
        search_output = Utils.run_cmd(search_cmd)
        search_results = JSON.parse(search_output)

        # Check if we found a matching conversation with summary
        if search_results.any? && search_results.first.dig("payload", "summary")
          summary = search_results.first.dig("payload", "summary")
          return summary unless summary.empty?
        end
      rescue => e
        logger.warn "Failed to search for existing summary for #{url}: #{e.message}"
      end

      # Generate new summary if none found
      begin
        # Fetch conversation data
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

        summary = Utils.llm_call(summary_prompt, model: :fast)
        return summary
      rescue => e
        logger.warn "Failed to generate summary for #{url}: #{e.message}"
        return url # Fallback to URL if summary generation fails
      end
    end

    # Prompt template for generating executive summaries of GitHub conversations.
    #
    # Variables:
    #   {{conversation}} - complete GitHub conversation data (JSON)
    # Output: Formal, narrative summary with contextual links
    EXECUTIVE_SUMMARY_PROMPT = <<~PROMPT
      # Executive summary instructions
      I need help summarizing a conversation from GitHub. Here are the rules I need you to follow:

      1. Concise, Informative Title: Begin with a clear, succinct title that encapsulates the main subject or decision at hand. The title should immediately set the context and importance of the issue or decision.
      2. Narrative-Driven Summary: Present the summary as a series of well-structured paragraphs. Avoid bullets, headers, or lists. Use a formal, professional tone, and ensure each paragraph builds logically on the previous one. Your goal is to convey a cohesive narrative of the conversation's evolution, from initial request to final decision or ongoing status.
      3. Complete Contextual Linking: Each time you mention or rely on a piece of information that came from a specific part of the conversation or a referenced resource, you must provide a direct link to it.
          - Comments by Contributors: When you cite or paraphrase something said by a participant, mention their @username plainly, then follow it immediately with a link in parentheses or integrated into the sentence.
            - For example: As @username suggested ([ref](URL)), the remediation plan requires additional time…
            - Note that @username itself is not linked. The link must be separate, placed after or within the sentence, not wrapping the username mention.
          - Events, Labels, or Status Changes: If you reference a point when the conversation moved stages or when a label was added/removed, follow the same linking pattern.
            - For example: Following the addition of the ROBOT: Ready for final review label (see [event record](URL)), the conversation shifted toward…
          - Referenced Documentation or Guides: If a guide, documentation page, or external resource is mentioned, embed the link in a phrase that clearly points to it.
            - For example: According to the shared key authentication guidelines (see [Flink documentation](URL)), this approach is discouraged…
            - All references that hinge upon a distinct resource, comment, or event available in the original conversation must be linked. No standalone links without contextual text; each link should be integrated into the narrative.
      4. Focus on Critical Content: Include only details that significantly influenced the direction, decisions, or outcomes. Omit administrative commentary, routine subscription messages, superficial technical details like code diffs, and exact merge timestamps, unless they directly influenced the final decision. Center on the key debates, decisions, constraints, and resolutions, and highlight the business or user impact rather than implementation minutiae.
      5. Alternatives, Status, and Next Steps: Where the conversation explored alternative solutions or future plans, clearly explain them and link to the comments or resources where these alternatives were discussed. If the resolution is partial or the decision involves further follow-up, summarize these implications and provide links to the final authoritative comments that set out those paths.
      6. Formal Tone, Dense Prose: Maintain a formal, authoritative tone. Write in complete, well-structured sentences. Integrate all references and links seamlessly, ensuring no extraneous formatting distracts from the narrative.
      7. Ignore Automated Bot Events: Do not include commentary, updates, or event records added by automated bots (e.g., @github-actions[bot]) unless they introduced a crucial piece of information or directly influenced the final outcome.

      By following these instructions, you will produce a tight executive summary that not only captures the essence of the conversation but also provides readers with direct, actionable links to every important piece of source material mentioned. This ensures that anyone reading the summary can delve deeper into the original conversation and resources as needed.
    PROMPT

    # Extracts conversation metadata from GitHub conversation data.
    def extract_conversation_metadata(conversation_data)
      # Determine type and extract conversation metadata
      conversation_type = if conversation_data["issue"]
        "issue"
      elsif conversation_data["pr"]
        "pull request"
      elsif conversation_data["discussion"]
        "discussion"
      else
        "unknown"
      end

      # Get the actual conversation object based on type
      conversation_obj = conversation_data["issue"] || conversation_data["pr"] || conversation_data["discussion"] || {}

      # Extract metadata for logging and return
      {
        type: conversation_type,
        title: conversation_obj["title"] || "Unknown title",
        state: conversation_obj["state"] || "unknown",
        comments_count: conversation_data["comments"]&.length || 0
      }
    end

    # Extracts qualifiers from user query and builds semantic search query.
    def build_semantic_query(user_query)
      # Extract repo: and author: qualifiers
      repo_match = user_query.match(/\brepo:(\S+)/)
      author_match = user_query.match(/\bauthor:(\S+)/)

      # Strip qualifiers from the query for semantic search
      semantic_query = user_query.dup
      semantic_query.gsub!(/\brepo:\S+/, '')
      semantic_query.gsub!(/\bauthor:\S+/, '')
      semantic_query.strip!

      # Clean up extra whitespace
      semantic_query.gsub!(/\s+/, ' ')

      {
        semantic_query: semantic_query,
        repo_filter: repo_match ? repo_match[1] : nil,
        author_filter: author_match ? author_match[1] : nil
      }
    end

    # Legacy method for fetching summaries directly from Qdrant (deprecated)
    #
    # This method searches Qdrant directly for conversation summaries using
    # URL-based filtering. It has been superseded by get_or_generate_summary
    # which provides better error handling and fallback strategies.
    #
    # ## Qdrant Search Strategy
    # Uses URL filtering to find exact conversation matches:
    # - **URL Filtering**: Applies exact URL filter to find specific conversations
    # - **JSON Format**: Requests structured JSON response for parsing
    # - **Single Result**: Limits to one result since URLs should be unique
    # - **Payload Extraction**: Retrieves summary from Qdrant payload data
    #
    # @deprecated Use get_or_generate_summary instead for better error handling
    # @param url [String] GitHub conversation URL to search for
    # @param collection [String] Qdrant collection name to search
    # @param script_dir [String] Directory containing semantic search executable
    # @return [String, nil] Existing summary if found, nil if not found or error occurs
    def fetch_summary_from_qdrant(url, collection, script_dir)
      begin
        # Build Qdrant search command with URL filter
        search_cmd = "#{script_dir}/semantic-search-github-conversations"
        search_cmd += " --collection #{Shellwords.escape(collection)}"
        search_cmd += " --filter url:#{Shellwords.escape(url)}"
        search_cmd += " --limit 1"
        search_cmd += " --format json"
        search_cmd += " #{Shellwords.escape('*')}"  # Dummy query since we're filtering by URL

        # Execute search and parse results
        search_output = Utils.run_cmd(search_cmd)
        search_results = JSON.parse(search_output)

        # Extract summary from first result if available
        if search_results.any?
          summary = search_results.first.dig("payload", "summary")
          return summary
        else
          return nil
        end
      rescue => e
        return nil # Graceful failure - calling code will handle fallback
      end
    end

    # Legacy method for generating conversation summaries (deprecated)
    #
    # This method generates new summaries for GitHub conversations using
    # a dedicated summarization script. It has been replaced by direct
    # LLM integration in get_or_generate_summary for better performance.
    #
    # ## Summary Generation Process
    # Uses external script for conversation summarization:
    # - **Script Execution**: Calls dedicated summarization script
    # - **Prompt Integration**: Passes executive summary prompt template
    # - **Cache Support**: Utilizes conversation caching when available
    # - **URL Processing**: Handles conversation fetching and processing
    #
    # @deprecated Use get_or_generate_summary instead for direct LLM integration
    # @param url [String] GitHub conversation URL to summarize
    # @param cache_path [String, nil] Optional cache directory for conversation data
    # @return [String] Generated summary or empty string if generation fails
    def generate_new_summary(url, cache_path = nil)
      begin
        # Build summarization command with template and options
        summarize_cmd = "#{File.dirname(__FILE__)}/../../bin/summarize-github-conversation"
        summarize_cmd += " --executive-summary-prompt #{Shellwords.escape(EXECUTIVE_SUMMARY_PROMPT)}"

        # Add caching support if available
        if cache_path
          summarize_cmd += " --cache-path #{Shellwords.escape(cache_path)}"
        end

        summarize_cmd += " #{Shellwords.escape(url)}"

        # Execute summarization and return cleaned result
        summary = Utils.run_cmd(summarize_cmd)
        return summary.strip
      rescue => e
        return "" # Return empty string on failure
      end
    end

    # Legacy wrapper method for summary retrieval (deprecated)
    #
    # This method provided a simple interface for getting conversation summaries
    # by trying Qdrant first, then generating new summaries. It has been replaced
    # by the more comprehensive implementation within the main exec() method.
    #
    # @deprecated This method is no longer used - functionality integrated into exec()
    # @param url [String] GitHub conversation URL
    # @param collection [String] Qdrant collection name
    # @param script_dir [String] Script directory path
    # @param cache_path [String, nil] Optional cache directory
    # @return [String] Conversation summary
    def get_or_generate_summary_legacy(url, collection, script_dir, cache_path = nil)
      # Try to fetch existing summary from Qdrant first
      existing_summary = fetch_summary_from_qdrant(url, collection, script_dir)
      return existing_summary if existing_summary && !existing_summary.empty?

      # Generate new summary if none found
      return generate_new_summary(url, cache_path)
    end

    # Enhanced semantic search command builder with comprehensive filter support
    #
    # This method builds complete semantic search commands with all available
    # filters and options. It extends the basic command builder with support
    # for repository filtering, author filtering, and advanced ordering options.
    #
    # ## Filter Integration
    # Supports comprehensive filtering options:
    # - **Temporal Filters**: created_after and created_before for date ranges
    # - **Repository Filters**: repo filter for specific repository targeting
    # - **Author Filters**: author filter for contributor-specific searches
    # - **Ordering Options**: Flexible ordering with key and direction specification
    #
    # ## Command Construction
    # Builds complete search commands with proper escaping:
    # - **Base Query**: Uses semantic_query or falls back to main query
    # - **Collection Specification**: Targets specific Qdrant collection
    # - **Result Limiting**: Applies top_k limit for result count
    # - **Format Specification**: Ensures JSON output for parsing
    # - **Parameter Validation**: Only adds filters when values are present
    #
    # @param search_plan [Hash] Comprehensive search plan containing:
    #   - :semantic_query => String Optimized semantic search query
    #   - :query => String Fallback query if semantic_query unavailable
    #   - :created_after => String Optional ISO date constraint
    #   - :created_before => String Optional ISO date constraint
    #   - :repo_filter => String Optional repository filter
    #   - :author_filter => String Optional author filter
    #   - :order_by => Hash Optional ordering with :key and :direction
    # @param script_dir [String] Directory containing search executable
    # @param collection [String] Target Qdrant collection name
    # @param top_k [Integer] Maximum number of results to retrieve
    # @return [String] Complete shell command ready for execution
    def build_semantic_search_command_with_filters(search_plan, script_dir, collection, top_k)
      # Build base command with query and essential parameters
      cmd = "#{script_dir}/semantic-search-github-conversations"
      cmd += " #{Shellwords.escape(search_plan[:semantic_query] || search_plan[:query])}"
      cmd += " --collection #{Shellwords.escape(collection)}"
      cmd += " --limit #{top_k}"
      cmd += " --format json"

      # Add temporal filters for date-based constraints
      if search_plan[:created_after]
        cmd += " --filter created_after:#{Shellwords.escape(search_plan[:created_after])}"
      end
      if search_plan[:created_before]
        cmd += " --filter created_before:#{Shellwords.escape(search_plan[:created_before])}"
      end

      # Add repository filter for specific repo targeting
      if search_plan[:repo_filter]
        cmd += " --filter repo:#{Shellwords.escape(search_plan[:repo_filter])}"
      end

      # Add author filter for contributor-specific searches
      if search_plan[:author_filter]
        cmd += " --filter author:#{Shellwords.escape(search_plan[:author_filter])}"
      end

      # Add ordering specification with key and direction
      if search_plan[:order_by]
        order_by_str = "#{search_plan[:order_by][:key]} #{search_plan[:order_by][:direction]}"
        cmd += " --order-by #{Shellwords.escape(order_by_str)}"
      end

      cmd
    end

    # Execute a single search plan and return normalized results.
    #
    # @param search_plan [Hash] Search plan with tool, query, etc.
    # @param script_dir [String] Directory containing search scripts
    # @param collection [String] Qdrant collection name
    # @param top_k [Integer] Maximum number of results
    # @return [Array<Hash>] Search results in normalized format
    def execute_single_search(search_plan, script_dir, collection, top_k)
      tool = search_plan[:tool]
      query = search_plan[:query]

      case tool
      when :semantic
        logger.info "Running semantic search with query: \"#{query}\""

        # Extract temporal and ordering qualifiers from the query for semantic search
        semantic_query_info = build_semantic_query(query)

        # Build updated search plan with extracted qualifiers for command construction
        updated_search_plan = search_plan.merge(semantic_query_info)

        # Build semantic search command with all parameters and constraints
        search_cmd = build_semantic_search_command(updated_search_plan, script_dir, collection, top_k)

        search_output = Utils.run_cmd(search_cmd)
        JSON.parse(search_output)

      when :keyword
        logger.info "Running keyword search with query: \"#{query}\""
        search_cmd = "#{script_dir}/search-github-conversations #{Shellwords.escape(query)}"

        search_output = Utils.run_cmd(search_cmd)
        keyword_results = JSON.parse(search_output)

        # Normalize keyword search results to match semantic search format
        # Keyword searches return URLs only, need to enrich with summaries
        keyword_results.map do |result|
          {
            "payload" => {
              "url" => result["url"],
              "summary" => "" # No summary available from keyword search - will be enriched later
            },
            "score" => 0.0 # No relevance score from keyword search
          }
        end.first(top_k)

      else
        logger.warn "Unknown search tool: #{tool}, skipping"
        []
      end
    end
  end
end
