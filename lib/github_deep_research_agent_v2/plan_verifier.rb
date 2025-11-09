# frozen_string_literal: true

require "json"
require_relative "models/plan"
require_relative "util/json_schema"

module GitHubDeepResearchAgentV2
  # PlanVerifier validates plans with deterministic rules
  class PlanVerifier
    MAX_ASPECTS = 8
    MIN_QUERIES_PER_ASPECT = 1

    def initialize(logger: nil)
      @logger = logger
    end

    # Verify a plan JSON string
    #
    # @param plan_json [String] JSON string representation of plan
    # @return [Hash] {valid: Boolean, errors: Array, plan: Plan|nil}
    def verify(plan_json)
      # Parse JSON
      unless Util::JSONSchema.valid_json?(plan_json)
        return {
          valid: false,
          errors: ["Invalid JSON format"],
          plan: nil
        }
      end

      plan_hash = JSON.parse(plan_json)
      plan = Models::Plan.from_h(plan_hash)

      # Run validation
      errors = validate(plan, plan_hash)

      {
        valid: errors.empty?,
        errors: errors,
        plan: errors.empty? ? plan : nil
      }
    rescue => e
      @logger&.error("Plan verification error: #{e.message}")
      {
        valid: false,
        errors: ["Verification error: #{e.message}"],
        plan: nil
      }
    end

    private

    # Validate plan structure and content
    def validate(plan, plan_hash)
      errors = []

      # Basic structure validation
      errors.concat(plan.validation_errors)

      # Additional semantic validation
      if plan.aspects.length > MAX_ASPECTS
        errors << "Too many aspects (max: #{MAX_ASPECTS})"
      end

      # Check for duplicate queries across aspects
      all_queries = plan.aspects.flat_map { |a| a["queries"] || [] }
      unless Util::JSONSchema.no_duplicates?(all_queries)
        errors << "Duplicate queries detected across aspects"
      end

      # Validate query formats
      plan.aspects.each_with_index do |aspect, i|
        queries = aspect["queries"] || []
        if queries.any? { |q| q.nil? || q.strip.empty? }
          errors << "Aspect #{i} contains empty queries"
        end
      end

      # Check required top-level keys exist
      required_keys = ["question", "aspects", "depth_limit", "breadth_limit"]
      required_keys.each do |key|
        unless plan_hash.key?(key)
          errors << "Missing required key: #{key}"
        end
      end

      errors
    end
  end
end
