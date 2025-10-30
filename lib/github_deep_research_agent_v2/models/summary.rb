# frozen_string_literal: true

module GitHubDeepResearchAgentV2
  module Models
    # Summary represents a distilled summary of a conversation with extracted facts
    class Summary
      attr_accessor :source_url, :facts, :topics, :confidence

      def initialize(attrs = {})
        @source_url = attrs[:source_url] || ""
        @facts = attrs[:facts] || []
        @topics = attrs[:topics] || []
        @confidence = attrs[:confidence] || 0.5
      end

      # Convert to flat JSON hash
      def to_h
        {
          source_url: @source_url,
          facts: @facts,
          topics: @topics,
          confidence: @confidence
        }
      end

      # Create summary from hash
      def self.from_h(hash)
        new(
          source_url: hash["source_url"] || hash[:source_url],
          facts: hash["facts"] || hash[:facts],
          topics: hash["topics"] || hash[:topics],
          confidence: hash["confidence"] || hash[:confidence]
        )
      end

      # Validate summary
      def valid?
        return false if @source_url.nil? || @source_url.strip.empty?
        return false if @facts.nil? || !@facts.is_a?(Array)
        return false if @topics.nil? || !@topics.is_a?(Array)
        return false if @confidence.nil? || @confidence < 0 || @confidence > 1
        true
      end
    end
  end
end
