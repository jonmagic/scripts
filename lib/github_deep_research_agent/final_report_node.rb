# lib/github_deep_research_agent/final_report_node.rb
#
# FinalReportNode: Generates comprehensive Markdown reports from research data

require_relative "../pocketflow"
require_relative "../utils"
require "json"
require "logger"

module GitHubDeepResearchAgent
  class FinalReportNode < Pocketflow::Node
    # Embedded prompt template for final report generation
    FINAL_REPORT_PROMPT = <<~PROMPT
    You are an expert analyst preparing a comprehensive Markdown report.

    ## Original Request
    {{request}}

    ## User Clarifications
    {{clarifications}}

    ## Research Corpus
    {{all_findings}}

    Produce a well-structured Markdown report based on the initial request and clarifications and cite relevant sources used to support your findings.

    **Style guide**

    * Use proper Markdown headings (`##`, `###`) and omit horizontal rules (`---`).
    * Every factual claim must be backed by an inline citation (full URL).
    * If status cannot be confirmed, mark it **Unknown** and note what evidence is missing.

    Return only the Markdown document—no extra commentary.
    PROMPT

    def prep(shared)
      @shared = shared # Store shared context
      LOG.info "=== FINAL REPORT PHASE ==="
      LOG.info "Generating final report from all gathered data..."

      compaction_note = ""
      if shared[:compaction_attempts] && shared[:compaction_attempts] > 0
        compaction_note = " (after #{shared[:compaction_attempts]} context compaction attempts)"
      end

      LOG.info "Research summary: #{shared[:memory][:hits].length} conversations analyzed#{compaction_note}, #{shared[:memory][:search_queries].length} queries used, #{shared[:current_depth] || 0} deep research iterations"

      LOG.debug do
        sources_list = shared[:memory][:hits].map.with_index do |hit, i|
          "  #{i + 1}. #{hit[:url]} (score: #{hit[:score]})"
        end.join("\n")
        "All conversation sources:\n#{sources_list}"
      end

      # Compile all findings
      all_findings = shared[:memory][:hits].map do |hit|
        <<~FINDING
        **Source**: #{hit[:url]}
        **Summary**: #{hit[:summary]}
        **Relevance Score**: #{hit[:score]}

        **Conversation Details**:
        #{JSON.pretty_generate(hit[:conversation])}
        FINDING
      end.join("\n\n---\n\n")

      prompt = Utils.fill_template(FINAL_REPORT_PROMPT, {
        request: shared[:request],
        clarifications: shared[:clarifications] || "None provided",
        all_findings: all_findings
      })

      LOG.debug "Calling LLM to generate final report..."
      prompt
    end

    def exec(prompt)
      begin
        # Use reasoning model for final report - this requires complex analysis and synthesis of all gathered data
        draft_answer = Utils.call_llm(prompt, @shared[:models][:reasoning])

        # Store the draft answer for claim verification
        @shared[:draft_answer] = draft_answer

        draft_answer
      rescue => e
        if Utils.context_too_large_error?(e.message) || Utils.rate_limit_error?(e.message)
          if Utils.rate_limit_error?(e.message)
            LOG.warn "Rate limit encountered: #{e.message}"
            LOG.info "Will attempt to compact context to reduce token usage and retry..."
          else
            LOG.warn "Context too large for model: #{e.message}"
            LOG.info "Will attempt to compact context and retry..."
          end

          # Store the error for reference
          @shared[:last_context_error] = e.message

          # Return a special signal to indicate compaction is needed
          return :context_too_large
        else
          # Re-raise other errors
          LOG.error "Unexpected error during final report generation: #{e.message}"
          raise e
        end
      end
    end

    def post(shared, prep_res, exec_res)
      # Check if we need to compact context
      if exec_res == :context_too_large
        LOG.info "Context too large, routing to compaction..."
        return "compact"
      end

      # Check if this is the first time generating the report (route to claim verification)
      unless shared[:claim_verification_completed]
        LOG.info "Routing to claim verification before final output"
        shared[:claim_verification_completed] = true
        return "verify"
      end

      # Final output with claim verification results
      LOG.info "=== FINAL REPORT ===\n\n"
      puts exec_res

      # Add note about unsupported claims if any
      if shared[:unsupported_claims] && shared[:unsupported_claims].any?
        puts "\n\n---\n\n"
        puts "**Note**: The following #{shared[:unsupported_claims].length} claims could not be fully verified against the available evidence:"
        shared[:unsupported_claims].each_with_index do |claim, i|
          puts "#{i + 1}. #{claim}"
        end
      end

      compaction_note = ""
      if shared[:compaction_attempts] && shared[:compaction_attempts] > 0
        compaction_note = " (after #{shared[:compaction_attempts]} context compaction attempts)"
      end

      verification_note = ""
      if shared[:claim_verification]
        verification_note = ", #{shared[:claim_verification][:total_claims]} claims verified (#{shared[:claim_verification][:supported_claims].length} supported, #{shared[:claim_verification][:unsupported_claims].length} unsupported)"
      end

      LOG.info "\n\n✓ Research complete! Total conversations analyzed: #{shared[:memory][:hits].length}#{compaction_note}#{verification_note}"

      "complete"
    end
  end
end
