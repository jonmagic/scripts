module GitHubDeepResearchAgent
  # FinalReportNode - Synthesizes research findings into a comprehensive Markdown report
  #
  # See lib/github_deep_research_agent.rb for architecture and workflow details.
  #
  # ## Overview
  # This node compiles all research data, clarifications, and findings into a well-structured
  # Markdown report, with citations and verification notes. Handles context compaction,
  # error recovery, and integrates claim verification before final output.
  #
  # ## Pipeline Position
  # - Input: Complete research dataset, clarifications, search history
  # - Output: Formatted Markdown report with citations and verification notes
  #
  # @example
  #   node = FinalReportNode.new
  #   prompt = node.prep(shared)
  #   report = node.exec(prompt)
  #   status = node.post(shared, prompt, report)
  class FinalReportNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Compile all research data and clarifications into a prompt for LLM report generation.
    #
    # @param shared [Hash] Workflow context with :memory, :request, :clarifications, etc.
    # @return [String] Formatted prompt for LLM
    def prep(shared)
      @shared = shared # Store shared context for access in exec() and post()
      logger.info "=== FINAL REPORT PHASE ==="
      logger.info "Generating final report from all gathered data..."

      # Generate compaction transparency note for process visibility
      compaction_note = ""
      if shared[:compaction_attempts] && shared[:compaction_attempts] > 0
        compaction_note = " (after #{shared[:compaction_attempts]} context compaction attempts)"
      end

      # Provide comprehensive research process summary
      logger.info "Research summary: #{shared[:memory][:hits].length} conversations analyzed#{compaction_note}, #{shared[:memory][:search_queries].length} queries used, #{shared[:current_depth] || 0} deep research iterations"

      # Generate detailed source listing for debugging and transparency
      logger.debug do
        sources_list = shared[:memory][:hits].map.with_index do |hit, i|
          "  #{i + 1}. #{hit[:url]} (score: #{hit[:score]})"
        end.join("\n")
        "All conversation sources:\n#{sources_list}"
      end

      # Compile all research findings into structured format for LLM processing
      # Each finding includes complete attribution and context for comprehensive analysis
      all_findings = shared[:memory][:hits].map do |hit|
        <<~FINDING
        **Source**: #{hit[:url]}
        **Summary**: #{hit[:summary]}
        **Relevance Score**: #{hit[:score]}

        **Conversation Details**:
        #{JSON.pretty_generate(hit[:conversation])}
        FINDING
      end.join("\n\n---\n\n")

      # Assemble complete prompt with all research context
      prompt = Utils.fill_template(FINAL_REPORT_PROMPT, {
        request: shared[:request],
        clarifications: shared[:clarifications] || "None provided",
        all_findings: all_findings
      })

      logger.debug "Calling LLM to generate final report..."
      prompt
    end

    # Generate draft report using reasoning LLM, with error handling for context/rate limits.
    #
    # @param prompt [String] Compiled research prompt
    # @return [String, Symbol] Draft report or :context_too_large
    def exec(prompt)
      begin
        # Use reasoning model for final report generation
        # This requires complex analysis and synthesis of all gathered data
        draft_answer = Utils.call_llm(prompt, @shared[:models][:reasoning])

        # Store the draft answer for downstream claim verification
        # This enables the ClaimVerifierNode to fact-check the generated content
        @shared[:draft_answer] = draft_answer

        draft_answer
      rescue => e
        # Handle context size and rate limiting errors with recovery strategies
        if Utils.context_too_large_error?(e.message) || Utils.rate_limit_error?(e.message)
          if Utils.rate_limit_error?(e.message)
            logger.warn "Rate limit encountered: #{e.message}"
            logger.info "Will attempt to compact context to reduce token usage and retry..."
          else
            logger.warn "Context too large for model: #{e.message}"
            logger.info "Will attempt to compact context and retry..."
          end

          # Store the error details for reference and debugging
          @shared[:last_context_error] = e.message

          # Return special signal to indicate compaction is needed
          # This triggers the workflow to route to ContextCompactionNode
          return :context_too_large
        else
          # Re-raise unexpected errors for proper debugging and handling
          logger.error "Unexpected error during final report generation: #{e.message}"
          raise e
        end
      end
    end

    # Coordinate workflow routing and produce final output after report generation.
    #
    # @param shared [Hash] Workflow context to update/read
    # @param prep_res [String] Prompt from prep()
    # @param exec_res [String, Symbol] Report or error signal from exec()
    # @return [String] Workflow routing or completion signal
    def post(shared, prep_res, exec_res)
      # Handle context size issues by routing to compaction
      if exec_res == :context_too_large
        logger.info "Context too large, routing to compaction..."
        return "compact"
      end

      # Route to claim verification for first-time report generation
      # This ensures all reports undergo fact-checking before final output
      unless shared[:claim_verification_completed]
        logger.info "Routing to claim verification before final output"
        shared[:claim_verification_completed] = true
        return "verify"
      end

      # Generate final report output with all enhancements
      logger.info "=== FINAL REPORT ===\n\n"
      puts exec_res

      # Add transparency note about unsupported claims if verification found issues
      if shared[:unsupported_claims] && shared[:unsupported_claims].any?
        puts "\n\n---\n\n"
        puts "**Note**: The following #{shared[:unsupported_claims].length} claims could not be fully verified against the available evidence:"
        shared[:unsupported_claims].each_with_index do |claim, i|
          puts "#{i + 1}. #{claim}"
        end
      end

      # Generate comprehensive process transparency notes
      compaction_note = ""
      if shared[:compaction_attempts] && shared[:compaction_attempts] > 0
        compaction_note = " (after #{shared[:compaction_attempts]} context compaction attempts)"
      end

      verification_note = ""
      if shared[:claim_verification]
        verification_note = ", #{shared[:claim_verification][:total_claims]} claims verified (#{shared[:claim_verification][:supported_claims].length} supported, #{shared[:claim_verification][:unsupported_claims].length} unsupported)"
      end

      # Provide final workflow completion summary with comprehensive metrics
      logger.info "\n\n✓ Research complete! Total conversations analyzed: #{shared[:memory][:hits].length}#{compaction_note}#{verification_note}"

      # Signal successful workflow completion
      "complete"
    end

    # Prompt for synthesizing research reports (see prep for usage).
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
  end
end
