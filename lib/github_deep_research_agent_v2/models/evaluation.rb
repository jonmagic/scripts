# frozen_string_literal: true

module GitHubDeepResearchAgentV2
  module Models
    # Evaluation represents mid-run assessment of research progress
    class Evaluation
      attr_accessor :coverage_score, :confidence_score, :source_diversity, 
                    :aspect_completion, :missing_aspects, :notes

      def initialize(attrs = {})
        @coverage_score = attrs[:coverage_score] || 0.0
        @confidence_score = attrs[:confidence_score] || 0.0
        @source_diversity = attrs[:source_diversity] || 0.0
        @aspect_completion = attrs[:aspect_completion] || 0.0
        @missing_aspects = attrs[:missing_aspects] || []
        @notes = attrs[:notes] || []
      end

      # Convert to flat JSON hash
      def to_h
        {
          coverage_score: @coverage_score,
          confidence_score: @confidence_score,
          source_diversity: @source_diversity,
          aspect_completion: @aspect_completion,
          missing_aspects: @missing_aspects,
          notes: @notes
        }
      end

      # Create evaluation from hash
      def self.from_h(hash)
        new(
          coverage_score: hash["coverage_score"] || hash[:coverage_score],
          confidence_score: hash["confidence_score"] || hash[:confidence_score],
          source_diversity: hash["source_diversity"] || hash[:source_diversity],
          aspect_completion: hash["aspect_completion"] || hash[:aspect_completion],
          missing_aspects: hash["missing_aspects"] || hash[:missing_aspects],
          notes: hash["notes"] || hash[:notes]
        )
      end

      # Validate evaluation
      def valid?
        return false if @coverage_score.nil? || @coverage_score < 0 || @coverage_score > 1
        return false if @confidence_score.nil? || @confidence_score < 0 || @confidence_score > 1
        return false if @source_diversity.nil? || @source_diversity < 0 || @source_diversity > 1
        return false if @aspect_completion.nil? || @aspect_completion < 0 || @aspect_completion > 1
        true
      end
    end
  end
end
