module GitHubDeepResearchAgent
  # ParallelClaimVerifierNode - Concurrent fact-checking for research reports
  #
  # This node extends the base ClaimVerifierNode to verify multiple claims
  # concurrently using Pocketflow's ParallelBatchNode capabilities. Each claim
  # is verified independently with its own evidence search and LLM verification.
  #
  # ## Parallelization Benefits
  # - **Evidence Search**: Multiple semantic searches run concurrently
  # - **LLM Verification**: Claim verification calls execute in parallel
  # - **Throughput**: Significant speed improvement for reports with many claims
  # - **Isolation**: Each claim verification is independent and thread-safe
  #
  # ## Thread Safety
  # - Each thread gets isolated copies of claim and evidence data
  # - Results are merged safely back to main verification context
  # - Error handling preserves individual verification failures
  #
  # @example
  #   # Drop-in replacement for ClaimVerifierNode
  #   verifier_node = GitHubDeepResearchAgent::ParallelClaimVerifierNode.new(logger: logger)
  #   final_node.on("verify", verifier_node)
  class ParallelClaimVerifierNode < Pocketflow::ParallelBatchNode
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Extract verifiable claims from draft research report using LLM.
    #
    # @param shared [Hash] Workflow context with :draft_answer, :models
    # @return [Array<String>, Symbol, nil] List of claims, :no_claims, or nil
    def prep(shared)
      @shared = shared # Store shared context for downstream method access
      logger.info "=== PARALLEL CLAIM VERIFICATION PHASE ==="

      # Validate that we have a draft report to analyze
      unless shared[:draft_answer]
        logger.info "No draft answer found for claim verification"
        return nil
      end

      logger.info "Extracting factual claims from draft answer for parallel verification..."

      # Extract claims using LLM analysis
      claims = extract_claims_from_report(shared[:draft_answer], shared[:models][:fast])

      # Handle edge case where no verifiable claims are found
      if claims.empty?
        logger.info "No factual claims found in draft answer, proceeding to final report"
        return :no_claims
      end

      logger.info "Found #{claims.length} claims to verify concurrently"
      claims
    end

    # Verify a single claim against evidence (called per thread).
    #
    # @param claim [String] Individual claim to verify
    # @return [Hash] Verification result with claim and status
    def exec(claim)
      thread_id = Thread.current.object_id
      logger.info "[Thread #{thread_id}] Verifying: #{claim.slice(0, 100)}..."

      begin
        # Extract configuration from shared context
        collection = @shared[:collection]
        script_dir = @shared[:script_dir]
        fast_model = @shared[:models][:fast]

        # Search for evidence related to this specific claim
        evidence = search_evidence_for_claim(claim, collection, script_dir, 3)

        # Use LLM to verify the claim against gathered evidence
        is_supported = verify_claim_against_evidence(claim, evidence, fast_model)

        status_emoji = is_supported ? "\u2713" : "\u2717"
        status_text = is_supported ? "SUPPORTED" : "UNSUPPORTED"
        logger.info "[Thread #{thread_id}] #{status_emoji} Claim #{status_text}"

        # Return structured verification result
        {
          claim: claim,
          supported: is_supported,
          evidence: evidence,
          thread_id: thread_id
        }
      rescue => e
        logger.warn "[Thread #{thread_id}] Verification failed: #{e.message}"
        {
          claim: claim,
          supported: false,
          evidence: "Error retrieving evidence: #{e.message}",
          error: e.message,
          thread_id: thread_id
        }
      end
    end

    # Aggregate parallel verification results and handle workflow routing.
    #
    # @param shared [Hash] Workflow context to update
    # @param prep_res [Array<String>, Symbol, nil] Claims from prep()
    # @param exec_res [Array<Hash>] Parallel verification results from exec()
    # @return [String] Workflow routing decision ("ok" or "fix")
    def post(shared, prep_res, exec_res)
      # Handle edge cases where verification wasn't performed
      return "ok" if prep_res.nil? || prep_res == :no_claims

      logger.info "=== AGGREGATING PARALLEL VERIFICATION RESULTS ==="

      # Separate supported and unsupported claims from parallel results
      supported_claims = []
      unsupported_claims = []
      verification_errors = []

      exec_res.each do |result|
        if result[:error]
          verification_errors << result
          unsupported_claims << result[:claim] # Treat errors as unsupported
        elsif result[:supported]
          supported_claims << result[:claim]
        else
          unsupported_claims << result[:claim]
        end
      end

      # Log verification summary
      logger.info "Parallel verification complete: #{supported_claims.length} supported, #{unsupported_claims.length} unsupported"

      # Log verification errors if any occurred
      if verification_errors.any?
        logger.warn "#{verification_errors.length} verification errors occurred:"
        verification_errors.each do |error_result|
          logger.warn "  #{error_result[:claim].slice(0, 100)}... - #{error_result[:error]}"
        end
      end

      # Log unsupported claims for transparency
      if unsupported_claims.any?
        logger.info "Found unsupported claims:"
        unsupported_claims.each_with_index do |claim, i|
          logger.info "  #{i + 1}. #{claim}"
        end
      end

      # Track verification attempts to prevent infinite retry loops
      verification_attempts = shared[:verification_attempts] || 0

      # Store comprehensive verification results in shared context
      verification_results = {
        total_claims: prep_res.length,
        supported_claims: supported_claims,
        unsupported_claims: unsupported_claims,
        verification_errors: verification_errors.length
      }

      shared[:claim_verification] = verification_results
      shared[:unsupported_claims] = unsupported_claims

      # Check if all claims were successfully verified
      if unsupported_claims.empty?
        logger.info "\u2713 All #{supported_claims.length} claims verified successfully, proceeding to final report"
        return "ok"
      else
        logger.info "Found #{unsupported_claims.length} unsupported claims out of #{prep_res.length} total"

        # Implement retry logic with maximum attempt limit
        if verification_attempts < 1
          shared[:verification_attempts] = verification_attempts + 1
          logger.info "Routing back to planner to gather better evidence for unsupported claims (attempt #{verification_attempts + 1}/1)"
          return "fix"
        else
          logger.info "Maximum verification attempts reached, proceeding with unsupported claims noted"
          return "ok"
        end
      end
    end

    private

    # Extract factual claims from research report using LLM.
    # (Same implementation as ClaimVerifierNode)
    def extract_claims_from_report(report, model = nil)
      prompt = Utils.fill_template(EXTRACT_CLAIMS_PROMPT, { report: report })

      begin
        llm_response = Utils.call_llm(prompt, model)

        # Clean up response to handle various formatting patterns
        cleaned_response = llm_response.strip
        if cleaned_response.start_with?('```json')
          cleaned_response = cleaned_response.gsub(/\A```json\s*/, '').gsub(/\s*```\z/, '')
        elsif cleaned_response.start_with?('```')
          cleaned_response = cleaned_response.gsub(/\A```\s*/, '').gsub(/\s*```\z/, '')
        end

        claims = JSON.parse(cleaned_response.strip)
        unless claims.is_a?(Array)
          return []
        end

        claims.first(25) # Limit to first 25 claims
      rescue JSON::ParserError
        []
      rescue
        []
      end
    end

    # Verify a single claim against evidence using LLM.
    # (Same implementation as ClaimVerifierNode)
    def verify_claim_against_evidence(claim, evidence, model = nil)
      prompt = Utils.fill_template(VERIFY_CLAIM_PROMPT, {
        claim: claim,
        evidence: evidence
      })

      begin
        llm_response = Utils.call_llm(prompt, model)
        result = llm_response.strip.upcase

        case result
        when "SUPPORTED"
          true
        when "UNSUPPORTED"
          false
        else
          false # Handle unexpected responses conservatively
        end
      rescue
        false # Handle any verification errors by defaulting to unsupported
      end
    end

    # Search for evidence related to a claim using semantic search.
    # (Same implementation as ClaimVerifierNode)
    def search_evidence_for_claim(claim, collection, script_dir, limit = 3)
      search_cmd = "#{script_dir}/semantic-search-github-conversations"
      search_cmd += " #{Shellwords.escape(claim)}"
      search_cmd += " --collection #{Shellwords.escape(collection)}"
      search_cmd += " --limit #{limit}"
      search_cmd += " --format json"

      begin
        search_output = Utils.run_cmd_safe(search_cmd)
        search_results = JSON.parse(search_output)

        if search_results.empty?
          return "No relevant evidence found."
        end

        # Format search results into structured evidence blocks
        evidence_parts = search_results.map.with_index do |result, i|
          url = result.dig("payload", "url") || "Unknown URL"
          summary = result.dig("payload", "summary") || "No summary available"
          score = result["score"] || 0.0

          "Evidence #{i + 1} (Score: #{score.round(3)}):\nSource: #{url}\nSummary: #{summary}"
        end

        evidence_parts.join("\n\n---\n\n")
      rescue => e
        "Error retrieving evidence: #{e.message}"
      end
    end

    # Prompt template for extracting verifiable claims from a research report.
    EXTRACT_CLAIMS_PROMPT = <<~PROMPT
      You are tasked with extracting factual claims from a research report. Extract specific, verifiable claims that can be fact-checked against evidence.

      Focus on:
      - Concrete statements about what happened, when, who was involved
      - Technical details and implementation specifics
      - Quantifiable metrics or outcomes
      - Process descriptions and workflows
      - Tool usage and configuration details

      Ignore:
      - Opinions, recommendations, or subjective statements
      - Vague or general statements
      - Future predictions or speculation

      Report to analyze:
      {{report}}

      Return ONLY a JSON array of claim strings, with no additional text or formatting. Maximum 25 claims.

      Example format:
      ["Claim 1 text here", "Claim 2 text here", "Claim 3 text here"]
    PROMPT

    # Prompt template for verifying a claim against provided evidence.
    VERIFY_CLAIM_PROMPT = <<~PROMPT
      You are a fact-checker tasked with verifying a claim against provided evidence.

      Claim to verify:
      {{claim}}

      Evidence to check against:
      {{evidence}}

      Instructions:
      1. Read the claim carefully
      2. Review all provided evidence
      3. Determine if the evidence supports, contradicts, or doesn't address the claim
      4. Consider partial support - if evidence only partially supports the claim, treat as unsupported

      Respond with exactly one word:
      - "SUPPORTED" if the evidence clearly supports the claim
      - "UNSUPPORTED" if the evidence contradicts the claim or doesn't provide sufficient support

      Response:
    PROMPT
  end
end
