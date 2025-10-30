# frozen_string_literal: true

require "digest"

module GitHubDeepResearchAgentV2
  module Models
    # Fact represents an atomic piece of information extracted from a source
    class Fact
      attr_accessor :id, :text, :source_urls, :aspect_id, :confidence, :extracted_at

      def initialize(attrs = {})
        @text = attrs[:text] || ""
        @source_urls = attrs[:source_urls] || []
        @aspect_id = attrs[:aspect_id]
        @confidence = attrs[:confidence] || 0.5
        @extracted_at = attrs[:extracted_at] || Time.now.utc.iso8601
        @id = attrs[:id] || generate_id
      end

      # Generate deterministic ID based on text content
      def generate_id
        "fact_#{Digest::SHA256.hexdigest(@text)[0..15]}"
      end

      # Convert to flat JSON hash (no nested objects beyond one level)
      def to_h
        {
          id: @id,
          text: @text,
          source_urls: @source_urls,
          aspect_id: @aspect_id,
          confidence: @confidence,
          extracted_at: @extracted_at
        }
      end

      # Create fact from hash
      def self.from_h(hash)
        new(
          id: hash["id"] || hash[:id],
          text: hash["text"] || hash[:text],
          source_urls: hash["source_urls"] || hash[:source_urls] || [],
          aspect_id: hash["aspect_id"] || hash[:aspect_id],
          confidence: hash["confidence"] || hash[:confidence],
          extracted_at: hash["extracted_at"] || hash[:extracted_at]
        )
      end

      # Validate fact
      def valid?
        return false if @text.nil? || @text.strip.empty?
        return false if @source_urls.nil? || !@source_urls.is_a?(Array) || @source_urls.empty?
        return false if @confidence.nil? || @confidence < 0 || @confidence > 1
        true
      end

      # Estimate token count (rough approximation)
      def token_count
        # Rough estimate: ~4 characters per token
        (@text.length / 4.0).ceil
      end
    end
  end
end
