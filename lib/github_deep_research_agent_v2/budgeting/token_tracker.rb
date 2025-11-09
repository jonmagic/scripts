# frozen_string_literal: true

module GitHubDeepResearchAgentV2
  module Budgeting
    # TokenTracker tracks token usage across different stages of research
    class TokenTracker
      attr_reader :usage

      STAGES = %i[planning research summarization evaluation report].freeze

      def initialize(budget: 60_000)
        @budget = budget
        @usage = {}
        STAGES.each { |stage| @usage[stage] = 0 }
      end

      # Record token usage for a stage
      def record(stage, tokens)
        raise ArgumentError, "Invalid stage: #{stage}" unless STAGES.include?(stage)
        @usage[stage] += tokens
      end

      # Get total token usage
      def total
        @usage.values.sum
      end

      # Get remaining budget
      def remaining
        [@budget - total, 0].max
      end

      # Check if budget is exhausted
      def exhausted?
        total >= @budget
      end

      # Check if approaching budget limit (>90%)
      def near_limit?
        total >= (@budget * 0.9)
      end

      # Get usage percentage
      def usage_percentage
        (total.to_f / @budget * 100).round(2)
      end

      # Predict if next operation would exceed budget
      def would_exceed?(predicted_tokens)
        (total + predicted_tokens) > @budget
      end

      # Get usage summary
      def summary
        {
          budget: @budget,
          total: total,
          remaining: remaining,
          usage_percentage: usage_percentage,
          breakdown: @usage.dup
        }
      end

      # Estimate tokens for text (rough approximation: ~4 chars per token)
      def self.estimate_tokens(text)
        return 0 if text.nil? || text.empty?
        (text.length / 4.0).ceil
      end
    end
  end
end
