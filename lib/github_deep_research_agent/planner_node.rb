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
    # Analyze research context and generate targeted search queries.
    #
    # @param shared [Hash] Workflow context with research state, findings, clarifications, etc.
    # @return [Hash, String, nil] Query structure, string, or nil if max depth
    def prep(shared)
      @shared = shared # Store shared context for access in exec() and post()
      depth = shared[:current_depth] || 0
      max_depth = shared[:max_depth]

      LOG.info "=== PLANNING PHASE (Iteration #{depth + 1}/#{max_depth}) ==="

      # Priority 1: Handle unsupported claims from verification process
      if shared[:unsupported_claims] && shared[:unsupported_claims].any?
        LOG.info "Focusing search on gathering evidence for #{shared[:unsupported_claims].length} unsupported claims"

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

        LOG.debug "Calling LLM to generate search query for unsupported claims..."
        llm_response = Utils.call_llm(prompt, shared[:models][:fast])
        refined_query = Utils.parse_semantic_search_response(llm_response)
        LOG.info "Generated claim verification search plan: #{refined_query}"

        return refined_query
      end

      LOG.info "Determining search strategy based on query analysis..."

      # Priority 2: Check iteration depth limits
      if depth >= max_depth
        LOG.info "Maximum depth reached, moving to final report"
        return nil
      end

      # Log iteration context for transparency
      if depth == 0
        LOG.info "First iteration - generating query different from initial research"
      end

      # Compile current research context for gap analysis
      findings_summary = shared[:memory][:notes].join("\n\n")
      previous_queries = shared[:memory][:search_queries].join(", ")

      LOG.debug do
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

        LOG.debug "Calling LLM to generate natural language search query..."
        llm_response = Utils.call_llm(prompt, shared[:models][:fast])
        refined_query = Utils.parse_semantic_search_response(llm_response)
        LOG.info "Generated semantic search plan: #{refined_query}"
      elsif search_mode == "keyword"
        # Generate GitHub search string for keyword search
        prompt = Utils.fill_template(GITHUB_SEARCH_PROMPT, {
          request: shared[:request],
          clarifications: shared[:clarifications] || ""
        })

        LOG.debug "Calling LLM to generate GitHub search query..."
        refined_query = Utils.call_llm(prompt, shared[:models][:fast])
        LOG.info "Generated GitHub search query: \"#{refined_query}\""
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

        LOG.debug "Calling LLM to generate semantic query..."
        semantic_response = Utils.call_llm(semantic_prompt, shared[:models][:fast])
        semantic_query = Utils.parse_semantic_search_response(semantic_response)
        LOG.info "Generated semantic query: #{semantic_query}"

        LOG.debug "Calling LLM to generate keyword query..."
        keyword_query = Utils.call_llm(keyword_prompt, shared[:models][:fast])
        LOG.info "Generated keyword query: \"#{keyword_query}\""

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
        LOG.info "Forced semantic search mode via --search-mode flag"
      elsif search_mode == "keyword"
        tool = :keyword
        LOG.info "Forced keyword search mode via --search-mode flag"
      else
        # Default to hybrid mode for comprehensive coverage
        tool = :hybrid
        LOG.info "Hybrid mode: Running both semantic and keyword searches"
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
          LOG.info "Single query provided, treating as semantic search in hybrid mode"
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
                LOG.debug "Extracted #{op} qualifier: #{qualifiers[op.to_sym]}"
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

      LOG.debug "Search plan: #{search_plan}"

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

      LOG.info "✓ Planning complete, proceeding to retrieval"
      LOG.debug "Moving to retrieval phase..."

      # Return nil to continue workflow with retrieval phase
      nil
    end

    # Template for generating semantic search strategies based on research question
    #
    # This template guides the LLM in creating semantic search strategies for GitHub
    # conversations related to the research question. It focuses on conceptual understanding
    # and thematic analysis rather than specific keyword matching.
    #
    # ## Template Variables
    # - **{{request}}**: The original research question requiring semantic investigation
    # - **{{clarifications}}**: User-provided context and clarifying responses
    # - **{{findings_summary}}**: Current research findings and accumulated knowledge
    # - **{{previous_queries}}**: Prior search attempts to avoid duplication
    #
    # ## Generated Output Format
    # The template produces structured semantic queries optimized for vector similarity:
    # - Conceptual terms that capture the essence of the research topic
    # - Thematic keywords related to problem domains and solutions
    # - Abstract concepts that may appear across multiple conversation types
    #
    # ## Search Strategy Focus
    # Semantic searches excel at finding conversations that:
    # - Discuss related concepts using different terminology
    # - Address similar problems with varied approaches
    # - Contain thematic overlap without exact keyword matches
    # - Represent conceptual evolution of ideas over time
    #
    # ## JSON Output Structure
    # Returns structured query with optional temporal constraints:
    # - **query**: Natural language query optimized for semantic similarity
    # - **created_after**: Optional ISO date for temporal filtering
    # - **created_before**: Optional ISO date for temporal filtering
    # - **order_by**: Optional ordering preference for result chronology
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

    # Template for generating GitHub search queries using operator-based syntax
    #
    # This template guides the LLM in creating precise GitHub search queries that leverage
    # GitHub's advanced search operators for targeted conversation discovery. It emphasizes
    # structured search syntax and temporal constraints for comprehensive results.
    #
    # ## Template Variables
    # - **{{request}}**: The original research question requiring operator-based search
    # - **{{clarifications}}**: User-provided context and clarifying responses
    # - **{{findings_summary}}**: Current research findings for query refinement
    # - **{{previous_queries}}**: Prior search attempts to avoid duplication
    #
    # ## Generated Search Operators
    # The template produces queries utilizing GitHub's search capabilities:
    # - **Scope Operators**: `repo:`, `org:`, `user:` for targeted searching
    # - **Type Operators**: `is:issue`, `is:pr`, `is:discussion` for content filtering
    # - **Temporal Operators**: `created:`, `updated:`, `closed:` for time-based filtering
    # - **Status Operators**: `state:open`, `state:closed` for lifecycle filtering
    # - **Metadata Operators**: `label:`, `assignee:`, `author:` for attribution filtering
    #
    # ## Search Strategy Focus
    # GitHub search queries excel at finding conversations that:
    # - Match specific repositories, organizations, or user contributions
    # - Fall within defined time periods or project phases
    # - Contain specific labels, assignments, or status conditions
    # - Represent particular types of development discussions
    #
    # ## JSON Output Structure
    # Returns structured query with comprehensive search parameters:
    # - **query**: GitHub search query with advanced operators
    # - **created_after**: Optional ISO date for temporal filtering
    # - **created_before**: Optional ISO date for temporal filtering
    # - **order_by**: Optional ordering preference for result chronology
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

    # Template for generating targeted queries to find evidence for unsupported claims
    #
    # This template specializes in creating search strategies for fact-checking and claim
    # verification. It focuses on finding concrete evidence, implementation details, and
    # verifiable information to support or refute specific research claims.
    #
    # ## Template Variables
    # - **{{request}}**: Original research question requiring claim verification
    # - **{{clarifications}}**: User-provided context and clarifying responses
    # - **{{unsupported_claims}}**: Specific claims that need evidential support
    # - **{{findings_summary}}**: Current research findings and evidence gaps
    # - **{{previous_queries}}**: Prior search attempts to avoid duplication
    #
    # ## Evidence Discovery Strategy
    # The template generates queries optimized for finding:
    # - **Implementation Evidence**: Direct proof of feature development and deployment
    # - **Technical Decisions**: Documented choices and their rationales
    # - **Concrete Examples**: Specific instances, metrics, and measurable outcomes
    # - **Timeline Information**: Project phases, release schedules, and progress updates
    # - **Status Verification**: Current implementation state and deployment status
    #
    # ## Search Result Structure
    # Produces structured queries with temporal and ordering constraints:
    # - Natural language queries optimized for comprehensive evidence discovery
    # - Optional temporal boundaries for focused historical analysis
    # - Ordering preferences to prioritize recent or chronological information
    # - JSON format for consistent parsing and execution by RetrieverNode
    #
    # ## Claim Verification Focus
    # The template emphasizes finding conversations that contain:
    # - Direct evidence of implementation status and completion
    # - Specific technical decisions and documented outcomes
    # - Concrete examples, metrics, and proof points
    # - Timeline information and project update communications
    # - Verifiable status indicators (merged PRs, releases, deployments)
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
