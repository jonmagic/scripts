module GitHubDeepResearchAgent
  # ClaimVerifierNode - Automated fact-checking for research reports
  #
  # See lib/github_deep_research_agent.rb for architecture and workflow details.
  #
  # ## Overview
  # This node extracts verifiable claims from draft research outputs and checks them
  # against evidence from the GitHub conversation database using LLMs and semantic search.
  # It ensures research accuracy and flags unsupported claims for further review.
  #
  # ## Pipeline Position
  # - Input: Draft answer/report from shared context
  # - Output: Verification results and unsupported claims
  #
  # @example
  #   node = ClaimVerifierNode.new
  #   claims = node.prep(shared)
  #   results = node.exec(claims)
  #   status = node.post(shared, claims, results)
  class ClaimVerifierNode < Pocketflow::Node
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
      logger.info "=== CLAIM VERIFICATION PHASE ==="

      # Validate that we have a draft report to analyze
      # Without a draft, there's nothing to fact-check
      unless shared[:draft_answer]
        logger.info "No draft answer found for claim verification"
        return nil
      end

      logger.info "Extracting factual claims from draft answer for verification..."

      # Extract claims using LLM analysis
      # The fast model is sufficient for this extraction task
      claims = extract_claims_from_report(shared[:draft_answer], shared[:models][:fast])

      # Handle edge case where no verifiable claims are found
      # This can happen with opinion-heavy or recommendation-focused reports
      if claims.empty?
        logger.info "No factual claims found in draft answer, proceeding to final report"
        return :no_claims
      end

      logger.info "Found #{claims.length} claims to verify"
      claims
    end

    # Verify extracted claims against evidence from GitHub conversations.
    #
    # @param claims [Array<String>, Symbol, nil] Claims to verify
    # @return [Hash, Symbol] Verification results or :no_claims
    def exec(claims)
      # Handle edge cases where no claims need verification
      return :no_claims if claims == :no_claims || claims.nil?

      logger.info "Verifying #{claims.length} claims against available evidence..."

      # Extract configuration from shared context
      collection = @shared[:collection]    # Qdrant collection name
      script_dir = @shared[:script_dir]    # Path to search scripts
      fast_model = @shared[:models][:fast] # LLM model for verification

      # Initialize result tracking arrays
      supported_claims = []
      unsupported_claims = []

      # Process each claim individually with progress tracking
      claims.each_with_index do |claim, i|
        logger.info "Verifying claim #{i + 1}/#{claims.length}: #{claim.slice(0, 100)}..."

        # Search for evidence related to this specific claim
        # Limit to 3 results to focus on most relevant evidence
        evidence = search_evidence_for_claim(claim, collection, script_dir, 3)

        # Use LLM to verify the claim against gathered evidence
        # This provides consistent, objective assessment
        is_supported = verify_claim_against_evidence(claim, evidence, fast_model)

        # Classify and track the claim based on verification result
        if is_supported
          supported_claims << claim
          logger.info "\u2713 Claim #{i + 1} SUPPORTED"
        else
          unsupported_claims << claim
          logger.info "\u2717 Claim #{i + 1} UNSUPPORTED"
        end
      end

      # Provide summary statistics for verification process
      logger.info "Verification complete: #{supported_claims.length} supported, #{unsupported_claims.length} unsupported"

      # Log unsupported claims for transparency and debugging
      if unsupported_claims.any?
        logger.info "Found unsupported claims:"
        unsupported_claims.each_with_index do |claim, i|
          logger.info "  #{i + 1}. #{claim}"
        end
      end

      # Return structured verification results
      {
        total_claims: claims.length,
        supported_claims: supported_claims,
        unsupported_claims: unsupported_claims
      }
    end

    # Handle verification results and workflow routing.
    #
    # @param shared [Hash] Workflow context to update
    # @param prep_res [Array<String>, Symbol, nil] Claims from prep()
    # @param exec_res [Hash, Symbol] Verification results from exec()
    # @return [String] Workflow routing decision ("ok" or "fix")
    def post(shared, prep_res, exec_res)
      # Handle edge cases where verification wasn't performed
      return "ok" if prep_res.nil? || exec_res == :no_claims

      # Track verification attempts to prevent infinite retry loops
      verification_attempts = shared[:verification_attempts] || 0

      # Store comprehensive verification results in shared context
      shared[:claim_verification] = exec_res
      shared[:unsupported_claims] = exec_res[:unsupported_claims]

      # Check if all claims were successfully verified
      if exec_res[:unsupported_claims].empty?
        logger.info "\u2713 All claims verified successfully, proceeding to final report"
        return "ok"
      else
        logger.info "Found #{exec_res[:unsupported_claims].length} unsupported claims"

        # Implement retry logic with maximum attempt limit
        # Allow only one retry to gather better evidence
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

    # Extract factual claims from research report using LLM.
    #
    # @param report [String] Research report text
    # @param model [String, nil] LLM model to use
    # @return [Array<String>] List of claims (max 25)
    def extract_claims_from_report(report, model = nil)
      # Fill prompt template with the report content
      prompt = Utils.fill_template(EXTRACT_CLAIMS_PROMPT, { report: report })

      begin
        # Call LLM to extract claims using structured prompt
        llm_response = Utils.call_llm(prompt, model)

        # Clean up response to handle various formatting patterns
        # LLMs sometimes wrap JSON in code blocks for readability
        cleaned_response = llm_response.strip
        if cleaned_response.start_with?('```json')
          # Remove ```json from start and ``` from end
          cleaned_response = cleaned_response.gsub(/\A```json\s*/, '').gsub(/\s*```\z/, '')
        elsif cleaned_response.start_with?('```')
          # Remove generic ``` from start and end
          cleaned_response = cleaned_response.gsub(/\A```\s*/, '').gsub(/\s*```\z/, '')
        end

        # Parse the cleaned JSON response
        claims = JSON.parse(cleaned_response.strip)

        # Validate that response is an array as expected
        unless claims.is_a?(Array)
          return []
        end

        # Limit to first 25 claims as specified in prompt
        claims.first(25)
      rescue JSON::ParserError
        # Handle JSON parsing failures gracefully
        []
      rescue
        # Handle any other extraction errors
        []
      end
    end

    # Verify a single claim against evidence using LLM.
    #
    # @param claim [String] Claim to verify
    # @param evidence [String] Evidence text
    # @param model [String, nil] LLM model to use
    # @return [Boolean] true if supported, false otherwise
    def verify_claim_against_evidence(claim, evidence, model = nil)
      # Fill verification prompt with claim and evidence context
      prompt = Utils.fill_template(VERIFY_CLAIM_PROMPT, {
        claim: claim,
        evidence: evidence
      })

      begin
        # Call LLM to perform verification analysis
        llm_response = Utils.call_llm(prompt, model)

        # Normalize response for consistent matching
        result = llm_response.strip.upcase

        # Map LLM response to boolean decision
        case result
        when "SUPPORTED"
          true
        when "UNSUPPORTED"
          false
        else
          # Handle unexpected responses conservatively
          false
        end
      rescue
        # Handle any verification errors by defaulting to unsupported
        # This ensures that technical failures don't incorrectly validate claims
        false
      end
    end

    # Search for evidence related to a claim using semantic search.
    #
    # @param claim [String] Claim text
    # @param collection [String] Qdrant collection name
    # @param script_dir [String] Path to search scripts
    # @param limit [Integer] Max results (default: 3)
    # @return [String] Formatted evidence or error message
    def search_evidence_for_claim(claim, collection, script_dir, limit = 3)
      # Construct semantic search command with proper escaping
      search_cmd = "#{script_dir}/semantic-search-github-conversations"
      search_cmd += " #{Shellwords.escape(claim)}"                    # Escaped query text
      search_cmd += " --collection #{Shellwords.escape(collection)}"  # Target collection
      search_cmd += " --limit #{limit}"                               # Result count limit
      search_cmd += " --format json"                                  # Output format

      begin
        # Execute search command and capture results
        search_output = Utils.run_cmd_safe(search_cmd)
        search_results = JSON.parse(search_output)

        # Handle case where no relevant conversations are found
        if search_results.empty?
          return "No relevant evidence found."
        end

        # Format search results into structured evidence blocks
        evidence_parts = search_results.map.with_index do |result, i|
          # Extract metadata from search result payload
          url = result.dig("payload", "url") || "Unknown URL"
          summary = result.dig("payload", "summary") || "No summary available"
          score = result["score"] || 0.0

          # Format each evidence piece with clear attribution
          "Evidence #{i + 1} (Score: #{score.round(3)}):\nSource: #{url}\nSummary: #{summary}"
        end

        # Join evidence blocks with clear separators for LLM parsing
        evidence_parts.join("\n\n---\n\n")
      rescue => e
        # Return descriptive error message for search failures
        "Error retrieving evidence: #{e.message}"
      end
    end

    # Prompt template for extracting verifiable claims from a research report.
    #
    # Variables:
    #   {{report}} - research report text
    # Output: JSON array of claim strings (max 25)
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
    #
    # Variables:
    #   {{claim}} - claim to verify
    #   {{evidence}} - evidence text
    # Output: One word, either "SUPPORTED" or "UNSUPPORTED"
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
