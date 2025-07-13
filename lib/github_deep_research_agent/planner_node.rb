# lib/github_deep_research_agent/planner_node.rb
#
# PlannerNode: Uses LLM to generate GitHub search queries based on the research request and clarifications.

require_relative "../pocketflow"
require_relative "../utils"

module GitHubDeepResearchAgent
  # PlannerNode: Uses LLM to generate GitHub search queries based on the research request and clarifications.
  #
  # This node uses the GITHUB_SEARCH_PROMPT to generate targeted GitHub search strings:
  # - Takes the research request and clarifications as input
  # - Generates GitHub-compatible search strings with operators when appropriate
  # - Defaults to keyword search since LLM produces GitHub search strings
  # - Supports --search-mode flag to override default behavior
  #
  # The generated queries are optimized for GitHub's search syntax and can include
  # operators like repo:, author:, label:, is:, created:, updated: when beneficial.
  class PlannerNode < Pocketflow::Node
    def prep(shared)
      @shared = shared # Store shared context
      depth = shared[:current_depth] || 0
      max_depth = shared[:max_depth]

      LOG.info "=== PLANNING PHASE (Iteration #{depth + 1}/#{max_depth}) ==="

      # Check if we have unsupported claims to research
      if shared[:unsupported_claims] && shared[:unsupported_claims].any?
        LOG.info "Focusing search on gathering evidence for #{shared[:unsupported_claims].length} unsupported claims"

        # Use special prompt for unsupported claims research
        unsupported_claims_list = shared[:unsupported_claims].map.with_index do |claim, i|
          "#{i + 1}. #{claim}"
        end.join("\n")

        findings_summary = shared[:memory][:notes].join("\n\n")
        previous_queries = shared[:memory][:search_queries].join(", ")

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

      # Check if we've reached max depth
      if depth >= max_depth
        LOG.info "Maximum depth reached, moving to final report"
        return nil
      end

      # For the first iteration, we need to generate a different query than what was used in InitialResearchNode
      # to avoid duplicates. We'll use the appropriate search mode logic.
      if depth == 0
        LOG.info "First iteration - generating query different from initial research"
      end

      # Generate query based on search mode
      findings_summary = shared[:memory][:notes].join("\n\n")
      previous_queries = shared[:memory][:search_queries].join(", ")

      LOG.debug do
        "Current research context:\n" \
        "  Previous queries: #{previous_queries}\n" \
        "  Total conversations found so far: #{shared[:memory][:hits].length}\n" \
        "  Research notes accumulated: #{shared[:memory][:notes].length}"
      end

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

        refined_query = {
          semantic: semantic_query,
          keyword: keyword_query
        }
      end

      refined_query
    end

    def exec(current_query)
      return nil if current_query.nil?

      # Store the current query for use by RetrieverNode
      @shared[:current_query] = current_query

      # Determine search mode based on flags and iteration depth
      search_mode = @shared[:search_mode]
      depth = @shared[:current_depth] || 0

      if search_mode == "semantic"
        tool = :semantic
        LOG.info "Forced semantic search mode via --search-mode flag"
      elsif search_mode == "keyword"
        tool = :keyword
        LOG.info "Forced keyword search mode via --search-mode flag"
      else
        # Hybrid mode: do both semantic and keyword searches
        tool = :hybrid
        LOG.info "Hybrid mode: Running both semantic and keyword searches"
      end

      # For hybrid mode, we need to check if we have separate semantic/keyword queries or a single query
      if tool == :hybrid
        # Check if current_query has separate semantic and keyword queries (from normal planning)
        # or if it's a single query (from unsupported claims research)
        if current_query.is_a?(Hash) && current_query[:semantic] && current_query[:keyword]
          # Normal hybrid mode with separate queries
          semantic_query = current_query[:semantic]
          search_plan = {
            tool: :hybrid,
            semantic_query: semantic_query[:query],
            keyword_query: current_query[:keyword]
          }

          # Add semantic search filters if present
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
          # Single query (likely from unsupported claims research) - treat as semantic search
          LOG.info "Single query provided, treating as semantic search in hybrid mode"
          tool = :semantic

          # Fall through to semantic search handling below
          search_plan = {
            tool: :semantic,
            query: current_query[:query] || current_query
          }

          # Add filters if present
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

      # Handle non-hybrid modes or fall-through from hybrid mode
      if tool != :hybrid
        # Handle both structured and legacy query formats
        if current_query.is_a?(Hash) && current_query[:query]
          # New structured format
          search_plan = {
            tool: tool,
            query: current_query[:query]
          }

          # Add filters if present
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
          # Legacy string format - extract potential qualifiers from the query for logging/UI
          qualifiers = {}
          if current_query.is_a?(String)
            %w[repo author label is created updated].each do |op|
              if current_query =~ /\b#{op}:(\S+)/i
                qualifiers[op.to_sym] = $1
                LOG.debug "Extracted #{op} qualifier: #{qualifiers[op.to_sym]}"
              end
            end
          end

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

    def post(shared, prep_res, exec_res)
      return "final" if prep_res.nil? # Max depth reached

      # Store the search plan for RetrieverNode
      shared[:next_search] = exec_res

      LOG.info "✓ Planning complete, proceeding to retrieval"
      LOG.debug "Moving to retrieval phase..."

      nil
    end

    # Embedded prompt templates
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
