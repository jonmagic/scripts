# frozen_string_literal: true

module GitHubDeepResearchAgentV2
  # PolicyEngine makes continuation/termination decisions
  class PolicyEngine
    ACTIONS = %i[continue replan finalize_full finalize_partial].freeze

    def initialize(
      min_coverage: 0.75,
      stop_if_confidence: 0.85,
      replan_max: 2,
      logger: nil
    )
      @min_coverage = min_coverage
      @stop_if_confidence = stop_if_confidence
      @replan_max = replan_max
      @logger = logger
    end

    # Decide next action based on current state
    #
    # @param state [Hash] Current research state
    #   - coverage_score [Float] Aspect completion percentage
    #   - confidence_score [Float] Overall confidence in findings
    #   - token_usage [Hash] Token usage breakdown
    #   - token_budget [Integer] Total budget
    #   - replans_used [Integer] Number of replans so far
    #   - aspect_gap_count [Integer] Number of uncovered aspects
    # @return [Symbol] One of: :continue, :replan, :finalize_full, :finalize_partial
    def decide(state)
      coverage = state[:coverage_score] || 0.0
      confidence = state[:confidence_score] || 0.0
      token_usage = state[:token_usage] || 0
      token_budget = state[:token_budget] || 60_000
      replans_used = state[:replans_used] || 0
      gap_count = state[:aspect_gap_count] || 0

      usage_ratio = token_usage.to_f / token_budget

      # Rule 1: Budget exhausted -> finalize partial
      if usage_ratio >= 1.0
        @logger&.info("PolicyEngine: Budget exhausted, finalizing partial")
        return :finalize_partial
      end

      # Rule 2: High confidence -> finalize full
      if confidence >= @stop_if_confidence
        @logger&.info("PolicyEngine: High confidence reached (#{confidence}), finalizing full")
        return :finalize_full
      end

      # Rule 3: Near budget limit and low coverage -> finalize partial
      if usage_ratio >= 0.8 && coverage < @min_coverage
        @logger&.info("PolicyEngine: Near budget limit with low coverage, finalizing partial")
        return :finalize_partial
      end

      # Rule 4: Significant gaps and replans available -> replan
      if gap_count >= 2 && replans_used < @replan_max
        @logger&.info("PolicyEngine: Significant gaps (#{gap_count}), requesting replan")
        return :replan
      end

      # Rule 5: Max replans reached but coverage low -> finalize partial
      if replans_used >= @replan_max && coverage < @min_coverage
        @logger&.info("PolicyEngine: Max replans reached with low coverage, finalizing partial")
        return :finalize_partial
      end

      # Rule 6: Max replans reached but coverage ok -> finalize full
      if replans_used >= @replan_max && coverage >= @min_coverage
        @logger&.info("PolicyEngine: Max replans reached with acceptable coverage, finalizing full")
        return :finalize_full
      end

      # Rule 7: Good coverage and under budget -> continue
      if coverage < @min_coverage && usage_ratio < 0.8
        @logger&.info("PolicyEngine: Continuing research (coverage: #{coverage}, budget: #{(usage_ratio * 100).round}%)")
        return :continue
      end

      # Default: continue if nothing else triggered
      @logger&.info("PolicyEngine: Default continue action")
      :continue
    end
  end
end
