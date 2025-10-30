# frozen_string_literal: true

module GitHubDeepResearchAgentV2
  module Models
    # Plan represents a structured research plan with aspects and execution parameters
    class Plan
      attr_accessor :question, :aspects, :depth_limit, :breadth_limit, 
                    :initial_hypotheses, :success_criteria

      def initialize(attrs = {})
        @question = attrs[:question] || ""
        @aspects = attrs[:aspects] || []
        @depth_limit = attrs[:depth_limit] || 3
        @breadth_limit = attrs[:breadth_limit] || 5
        @initial_hypotheses = attrs[:initial_hypotheses] || []
        @success_criteria = attrs[:success_criteria] || []
      end

      # Convert plan to hash for serialization
      def to_h
        {
          question: @question,
          aspects: @aspects,
          depth_limit: @depth_limit,
          breadth_limit: @breadth_limit,
          initial_hypotheses: @initial_hypotheses,
          success_criteria: @success_criteria
        }
      end

      # Create plan from hash
      def self.from_h(hash)
        new(
          question: hash["question"] || hash[:question],
          aspects: hash["aspects"] || hash[:aspects],
          depth_limit: hash["depth_limit"] || hash[:depth_limit],
          breadth_limit: hash["breadth_limit"] || hash[:breadth_limit],
          initial_hypotheses: hash["initial_hypotheses"] || hash[:initial_hypotheses],
          success_criteria: hash["success_criteria"] || hash[:success_criteria]
        )
      end

      # Validate plan structure
      def valid?
        return false if @question.nil? || @question.strip.empty?
        return false if @aspects.nil? || !@aspects.is_a?(Array)
        return false if @depth_limit.nil? || @depth_limit < 1 || @depth_limit > 5
        return false if @breadth_limit.nil? || @breadth_limit < 1
        return false if @aspects.length > @breadth_limit
        
        # Each aspect must have required fields
        @aspects.all? do |aspect|
          aspect.is_a?(Hash) &&
            aspect["id"] &&
            aspect["title"] &&
            aspect["queries"] &&
            aspect["queries"].is_a?(Array) &&
            aspect["queries"].length >= 1
        end
      end

      # Get validation errors
      def validation_errors
        errors = []
        errors << "Question is required" if @question.nil? || @question.strip.empty?
        errors << "Aspects must be an array" if @aspects.nil? || !@aspects.is_a?(Array)
        errors << "Depth limit must be between 1 and 5" if @depth_limit.nil? || @depth_limit < 1 || @depth_limit > 5
        errors << "Breadth limit must be at least 1" if @breadth_limit.nil? || @breadth_limit < 1
        errors << "Number of aspects exceeds breadth limit" if @aspects.length > @breadth_limit

        @aspects.each_with_index do |aspect, i|
          unless aspect.is_a?(Hash)
            errors << "Aspect #{i} must be a hash"
            next
          end
          errors << "Aspect #{i} missing id" unless aspect["id"]
          errors << "Aspect #{i} missing title" unless aspect["title"]
          errors << "Aspect #{i} missing queries" unless aspect["queries"]
          errors << "Aspect #{i} queries must be an array" unless aspect["queries"].is_a?(Array)
          errors << "Aspect #{i} must have at least 1 query" unless aspect["queries"]&.length&.>= 1
        end

        errors
      end
    end
  end
end
