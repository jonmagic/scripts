# lib/github_deep_research_agent/claim_verifier_node.rb
#
# Handles fact-checking and claim verification against GitHub conversations evidence

require "json"
require "shellwords"
require_relative "../../lib/pocketflow"
require_relative "../../lib/utils"

module GitHubDeepResearchAgent
  class ClaimVerifierNode < Pocketflow::Node
    def prep(shared)
      @shared = shared # Store shared context
      puts "=== CLAIM VERIFICATION PHASE ==="

      # Check if we already have a draft answer to verify
      unless shared[:draft_answer]
        puts "No draft answer found for claim verification"
        return nil
      end

      puts "Extracting factual claims from draft answer for verification..."

      # Extract claims from the draft answer
      claims = extract_claims_from_report(shared[:draft_answer], shared[:models][:fast])

      if claims.empty?
        puts "No factual claims found in draft answer, proceeding to final report"
        return :no_claims
      end

      puts "Found #{claims.length} claims to verify"
      claims
    end

    def exec(claims)
      return :no_claims if claims == :no_claims || claims.nil?

      puts "Verifying #{claims.length} claims against available evidence..."

      collection = @shared[:collection]
      script_dir = @shared[:script_dir]
      fast_model = @shared[:models][:fast]

      supported_claims = []
      unsupported_claims = []

      claims.each_with_index do |claim, i|
        puts "Verifying claim #{i + 1}/#{claims.length}: #{claim.slice(0, 100)}..."

        # Search for evidence related to this claim
        evidence = search_evidence_for_claim(claim, collection, script_dir, 3)

        # Verify the claim against the evidence
        is_supported = verify_claim_against_evidence(claim, evidence, fast_model)

        if is_supported
          supported_claims << claim
          puts "✓ Claim #{i + 1} SUPPORTED"
        else
          unsupported_claims << claim
          puts "✗ Claim #{i + 1} UNSUPPORTED"
        end
      end

      puts "Verification complete: #{supported_claims.length} supported, #{unsupported_claims.length} unsupported"

      if unsupported_claims.any?
        puts "Found unsupported claims:"
        unsupported_claims.each_with_index do |claim, i|
          puts "  #{i + 1}. #{claim}"
        end
      end

      {
        total_claims: claims.length,
        supported_claims: supported_claims,
        unsupported_claims: unsupported_claims
      }
    end

    def post(shared, prep_res, exec_res)
      return "ok" if prep_res.nil? || exec_res == :no_claims

      verification_attempts = shared[:verification_attempts] || 0

      # Store verification results
      shared[:claim_verification] = exec_res
      shared[:unsupported_claims] = exec_res[:unsupported_claims]

      if exec_res[:unsupported_claims].empty?
        puts "✓ All claims verified successfully, proceeding to final report"
        return "ok"
      else
        puts "Found #{exec_res[:unsupported_claims].length} unsupported claims"

        # Allow only one retry to gather better evidence
        if verification_attempts < 1
          shared[:verification_attempts] = verification_attempts + 1
          puts "Routing back to planner to gather better evidence for unsupported claims (attempt #{verification_attempts + 1}/1)"
          return "fix"
        else
          puts "Maximum verification attempts reached, proceeding with unsupported claims noted"
          return "ok"
        end
      end
    end

    # Extracts claims from a report using LLM analysis.
    def extract_claims_from_report(report, model = nil)
      prompt = Utils.fill_template(EXTRACT_CLAIMS_PROMPT, { report: report })

      begin
        llm_response = Utils.call_llm(prompt, model)

        # Clean up response - remove markdown code blocks if present
        cleaned_response = llm_response.strip
        if cleaned_response.start_with?('```json')
          # Remove ```json from start and ``` from end
          cleaned_response = cleaned_response.gsub(/\A```json\s*/, '').gsub(/\s*```\z/, '')
        elsif cleaned_response.start_with?('```')
          # Remove generic ``` from start and end
          cleaned_response = cleaned_response.gsub(/\A```\s*/, '').gsub(/\s*```\z/, '')
        end

        claims = JSON.parse(cleaned_response.strip)

        unless claims.is_a?(Array)
          return []
        end

        # Limit to first 25 claims as specified
        claims.first(25)
      rescue JSON::ParserError
        []
      rescue
        []
      end
    end

    # Verifies a single claim against evidence using LLM.
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
          false
        end
      rescue
        false
      end
    end

    # Searches for evidence related to a specific claim.
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

        # Extract summaries from search results
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

    # Prompt constants used by claim verification functions
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
