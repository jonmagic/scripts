module GitHubDeepResearchAgent
  # PlannerNode - Generates search strategies for iterative GitHub research
  #
  # See lib/github_deep_research_agent.rb for architecture and workflow details.
  #
  # ## Overview
  # This node analyzes accumulated findings and context to generate targeted search queries
  # and strategies for iterative research, including claim verification and multi-modal search.
  #
  # ## Pipeline Position
  # - Input: Research context, findings, clarifications, unsupported claims
  # - Output: Structured search plans for RetrieverNode
  #
  # @example
  #   node = PlannerNode.new
  #   query = node.prep(shared)
  #   plan = node.exec(query)
  #   node.post(shared, query, plan)
  class PlannerNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Analyze research context and generate targeted search queries.
    #
    # @param shared [Hash] Workflow context with research state, findings, clarifications, etc.
    # @return [Hash, String, nil] Query structure, string, or nil if max depth
    def prep(shared)
      @shared = shared # Store shared context for access in exec() and post()
      depth = shared[:current_depth] || 0
      max_depth = shared[:max_depth]

      logger.info "=== PLANNING PHASE (Iteration #{depth + 1}/#{max_depth}) ==="

      # Priority 1: Handle unsupported claims from verification process
      if shared[:unsupported_claims] && shared[:unsupported_claims].any?
        logger.info "Focusing search on gathering evidence for #{shared[:unsupported_claims].length} unsupported claims"

        # Format unsupported claims for LLM processing
        unsupported_claims_list = shared[:unsupported_claims].map.with_index do |claim, i|
          "#{i + 1}. #{claim}"
        end.join("\n")

        # Compile research context for claim verification
        findings_summary = shared[:memory][:notes].join("\n\n")
        previous_queries = shared[:memory][:search_queries].join(", ")

        # Generate claim verification query using specialized prompt
        prompt = Utils.fill_template(UNSUPPORTED_CLAIMS_RESEARCH_PROMPT, {
          request: shared[:request],
          clarifications: shared[:clarifications] || "",
          unsupported_claims: unsupported_claims_list,
          findings_summary: findings_summary,
          previous_queries: previous_queries
        })

        logger.debug "Calling LLM to generate search query for unsupported claims..."
        llm_response = Utils.call_llm(prompt, shared[:models][:fast])
        refined_query = Utils.parse_semantic_search_response(llm_response)
        logger.info "Generated claim verification search plan: #{refined_query}"

        return refined_query
      end

      logger.info "Determining search strategy based on query analysis..."

      # Priority 2: Check iteration depth limits
      if depth >= max_depth
        logger.info "Maximum depth reached, moving to final report"
        return nil
      end

      # Log iteration context for transparency
      if depth == 0
        logger.info "First iteration - generating query different from initial research"
      end

      # Compile current research context for gap analysis
      findings_summary = shared[:memory][:notes].join("\n\n")
      previous_queries = shared[:memory][:search_queries].join(", ")

      logger.debug do
        "Current research context:\n" \
        "  Previous queries: #{previous_queries}\n" \
        "  Total conversations found so far: #{shared[:memory][:hits].length}\n" \
        "  Research notes accumulated: #{shared[:memory][:notes].length}"
      end

      # Priority 3: Generate queries based on configured search mode
      search_mode = shared[:search_mode]

      if search_mode == "semantic"
        # Generate natural language query for semantic search
        prompt = Utils.fill_template(SEMANTIC_RESEARCH_PROMPT, {
          request: shared[:request],
          clarifications: shared[:clarifications] || "",
          findings_summary: findings_summary,
          previous_queries: previous_queries
        })

        logger.debug "Calling LLM to generate natural language search query..."
        llm_response = Utils.call_llm(prompt, shared[:models][:fast])
        refined_query = Utils.parse_semantic_search_response(llm_response)
        logger.info "Generated semantic search plan: #{refined_query}"
      elsif search_mode == "keyword"
        # Generate GitHub search string for keyword search
        prompt = Utils.fill_template(GITHUB_SEARCH_PROMPT, {
          request: shared[:request],
          clarifications: shared[:clarifications] || ""
        })

        logger.debug "Calling LLM to generate GitHub search query..."
        refined_query = Utils.call_llm(prompt, shared[:models][:fast])
        logger.info "Generated GitHub search query: \"#{refined_query}\""
      else
        # Hybrid mode: generate both semantic and keyword queries
        semantic_prompt = Utils.fill_template(SEMANTIC_RESEARCH_PROMPT, {
          request: shared[:request],
          clarifications: shared[:clarifications] || "",
          findings_summary: findings_summary,
          previous_queries: previous_queries
        })

        keyword_prompt = Utils.fill_template(GITHUB_SEARCH_PROMPT, {
          request: shared[:request],
          clarifications: shared[:clarifications] || ""
        })

        logger.debug "Calling LLM to generate semantic query..."
        semantic_response = Utils.call_llm(semantic_prompt, shared[:models][:fast])
        semantic_query = Utils.parse_semantic_search_response(semantic_response)
        logger.info "Generated semantic query: #{semantic_query}"

        logger.debug "Calling LLM to generate keyword query..."
        keyword_query = Utils.call_llm(keyword_prompt, shared[:models][:fast])
        logger.info "Generated keyword query: \"#{keyword_query}\""

        # Combine both queries into structured hybrid format
        refined_query = {
          semantic: semantic_query,
          keyword: keyword_query
        }
      end

      refined_query
    end

    # Transform queries into structured search plans for RetrieverNode.
    #
    # @param current_query [Hash, String, nil] Query from prep()
    # @return [Hash, nil] Search plan or nil if no query
    def exec(current_query)
      # Handle maximum depth scenario where no further search is needed
      return nil if current_query.nil?

      # Store the current query for potential access by other workflow components
      @shared[:current_query] = current_query

      # Determine search mode based on configuration and iteration context
      search_mode = @shared[:search_mode]
      depth = @shared[:current_depth] || 0

      # Initial tool selection based on configured search mode
      if search_mode == "semantic"
        tool = :semantic
        logger.info "Forced semantic search mode via --search-mode flag"
      elsif search_mode == "keyword"
        tool = :keyword
        logger.info "Forced keyword search mode via --search-mode flag"
      else
        # Default to hybrid mode for comprehensive coverage
        tool = :hybrid
        logger.info "Hybrid mode: Running both semantic and keyword searches"
      end

      # Handle hybrid mode with sophisticated query format detection
      if tool == :hybrid
        # Check if current_query has separate semantic and keyword components
        # This distinguishes normal planning from claim verification scenarios
        if current_query.is_a?(Hash) && current_query[:semantic] && current_query[:keyword]
          # Normal hybrid mode with separate queries from dual LLM generation
          semantic_query = current_query[:semantic]
          search_plan = {
            tool: :hybrid,
            semantic_query: semantic_query[:query],
            keyword_query: current_query[:keyword]
          }

          # Add semantic search filters if present in the structured query
          if semantic_query[:created_after]
            search_plan[:created_after] = semantic_query[:created_after]
          end
          if semantic_query[:created_before]
            search_plan[:created_before] = semantic_query[:created_before]
          end
          if semantic_query[:order_by]
            search_plan[:order_by] = semantic_query[:order_by]
          end
        else
          # Single query provided (likely from unsupported claims research)
          # Treat as semantic search since claim verification benefits from vector similarity
          logger.info "Single query provided, treating as semantic search in hybrid mode"
          tool = :semantic

          # Fall through to semantic search handling below
          search_plan = {
            tool: :semantic,
            query: current_query[:query] || current_query
          }

          # Add filters if present in structured format
          if current_query.is_a?(Hash)
            if current_query[:created_after]
              search_plan[:created_after] = current_query[:created_after]
            end
            if current_query[:created_before]
              search_plan[:created_before] = current_query[:created_before]
            end
            if current_query[:order_by]
              search_plan[:order_by] = current_query[:order_by]
            end
          end
        end
      end

      # Handle non-hybrid modes or fall-through from hybrid mode logic
      if tool != :hybrid
        # Process both structured and legacy query formats
        if current_query.is_a?(Hash) && current_query[:query]
          # New structured format with explicit query and filter fields
          search_plan = {
            tool: tool,
            query: current_query[:query]
          }

          # Add temporal and ordering filters if present
          if current_query[:created_after]
            search_plan[:created_after] = current_query[:created_after]
          end
          if current_query[:created_before]
            search_plan[:created_before] = current_query[:created_before]
          end
          if current_query[:order_by]
            search_plan[:order_by] = current_query[:order_by]
          end
        else
          # Legacy string format - extract potential qualifiers for logging and debugging
          qualifiers = {}
          if current_query.is_a?(String)
            # Parse GitHub search operators from the query string
            %w[repo author label is created updated].each do |op|
              if current_query =~ /\b#{op}:(\S+)/i
                qualifiers[op.to_sym] = $1
                logger.debug "Extracted #{op} qualifier: #{qualifiers[op.to_sym]}"
              end
            end
          end

          # Create search plan with extracted qualifiers for reference
          search_plan = {
            tool: tool,
            query: current_query,
            qualifiers: qualifiers
          }
        end
      end

      logger.debug "Search plan: #{search_plan}"

      search_plan
    end

    # Store search plan and coordinate workflow routing.
    #
    # @param shared [Hash] Workflow context to update
    # @param prep_res [Hash, String, nil] Query from prep()
    # @param exec_res [Hash, nil] Search plan from exec()
    # @return [String, nil] "final" if max depth, else nil
    def post(shared, prep_res, exec_res)
      # Handle maximum depth scenario by routing to final report generation
      return "final" if prep_res.nil? # Max depth reached

      # Store the comprehensive search plan for RetrieverNode execution
      shared[:next_search] = exec_res

      logger.info "✓ Planning complete, proceeding to retrieval"
      logger.debug "Moving to retrieval phase..."

      # Return nil to continue workflow with retrieval phase
      nil
    end

    # Prompt template for generating semantic search strategies.
    #
    # Variables:
    #   {{request}} - research question
    #   {{clarifications}} - user clarifications
    #   {{findings_summary}} - current findings
    #   {{previous_queries}} - prior queries
    # Output: JSON object with query, created_after, created_before, order_by
    SEMANTIC_RESEARCH_PROMPT = <<~PROMPT
      You are an expert researcher mining GitHub conversations for actionable evidence.

      ## Original Request
      {{request}}

      ## User Clarifications
      {{clarifications}}

      ## Findings So Far
      {{findings_summary}}

      ## Prior Search Queries
      {{previous_queries}}

      **Goal**
      Identify the most significant information gaps and craft one new natural-language search query (≤ 2 sentences, no operators) that will surface GitHub conversations to close them.
      Gaps may include — but are not limited to — missing implementation details, unclear project status (Implemented · In Progress · Proposed · Abandoned · Unknown), decisions, trade-offs, or alternative solutions.

      When project "doneness" is uncertain, bias your query toward finding evidence that proves or disproves implementation (e.g. merged PRs, release notes, deployment comments). Otherwise, target whatever gap is highest-impact.

      If helpful, suggest date ranges in ISO8601 format (created_after / created_before) to narrow the search.
      If appropriate, specify ordering (order_by: created_at asc|desc).

      Return a JSON object with:
      - "query": the natural language search query
      - "created_after": ISO date string (optional)
      - "created_before": ISO date string (optional)
      - "order_by": "created_at asc" or "created_at desc" (optional)

      Do not use markdown code blocks - return only the raw JSON object.

      *Examples*
      {"query": "Confirmation that client-side rate limiting is merged and live", "created_after": "2024-01-01"}
      {"query": "Alternative approaches to large-table migration performance", "order_by": "created_at desc"}
      {"query": "Discussion showing why the authentication redesign was abandoned"}
    PROMPT

    # Prompt template for generating GitHub search queries using operator-based syntax.
    #
    # Variables:
    #   {{request}} - research question
    #   {{clarifications}} - user clarifications
    #   {{findings_summary}} - current findings
    #   {{previous_queries}} - prior queries
    # Output: search string (≤ 5 terms/operators)
    GITHUB_SEARCH_PROMPT = <<~PROMPT
      You are GitHub's top search power-user.

      ## Research request
      {{request}}

      ## Known clarifications
      {{clarifications}}

      Return **one** GitHub search string that is likely to surface the best discussions.
      • ≤ 5 terms/operators.
      • Prefer operators when obvious (`repo:`, `author:`, `label:`, `is:`, `created:`, `updated:`).
      • Otherwise fall back to 2-3 strong keywords.
      Output only the search string, nothing else.
    PROMPT

    # Prompt template for generating queries to find evidence for unsupported claims.
    #
    # Variables:
    #   {{request}} - research question
    #   {{clarifications}} - user clarifications
    #   {{unsupported_claims}} - claims needing evidence
    #   {{findings_summary}} - current findings
    #   {{previous_queries}} - prior queries
    # Output: JSON object with query, created_after, created_before, order_by
    UNSUPPORTED_CLAIMS_RESEARCH_PROMPT = <<~PROMPT
      You are an expert researcher focusing on verifying unsupported claims from a research report.

      ## Original Request
      {{request}}

      ## User Clarifications
      {{clarifications}}

      ## Unsupported Claims That Need Verification
      {{unsupported_claims}}

      ## Previous Findings
      {{findings_summary}}

      ## Prior Search Queries
      {{previous_queries}}

      **Goal**
      Generate a natural-language search query (≤ 2 sentences, no operators) specifically designed to find GitHub conversations that could provide evidence for the unsupported claims listed above.

      Focus on finding conversations that contain:
      - Direct evidence of implementation status
      - Specific technical decisions and outcomes
      - Concrete examples or proof points
      - Timeline information and project updates

      Return a JSON object with:
      - "query": the natural language search query targeting evidence for unsupported claims
      - "created_after": ISO date string (optional)
      - "created_before": ISO date string (optional)
      - "order_by": "created_at asc" or "created_at desc" (optional)

      Do not use markdown code blocks - return only the raw JSON object.

      *Examples*
      {"query": "Evidence of feature implementation and merge status with specific PR numbers", "order_by": "created_at desc"}
      {"query": "Performance measurement results and optimization outcomes with concrete metrics"}
    PROMPT
  end
end
