# frozen_string_literal: true

require "digest"
require "json"

module GitHubDeepResearchAgentV2
  module Models
    # Artifact represents a piece of research data stored externally
    class Artifact
      VALID_TYPES = %w[
        plan_node query result_raw summary fact 
        expansion_suggestion evaluation final_report
      ].freeze

      attr_accessor :id, :type, :data, :created_at

      def initialize(attrs = {})
        @type = attrs[:type]
        @data = attrs[:data] || {}
        @created_at = attrs[:created_at] || Time.now.utc.iso8601
        @id = attrs[:id] || generate_id
      end

      # Generate deterministic ID based on type and content
      def generate_id
        content = "#{@type}:#{JSON.generate(@data)}"
        "#{@type}_#{Digest::SHA256.hexdigest(content)[0..15]}"
      end

      # Convert to hash for serialization (flat JSON)
      def to_h
        {
          id: @id,
          type: @type,
          data: @data,
          created_at: @created_at
        }
      end

      # Create artifact from hash
      def self.from_h(hash)
        new(
          id: hash["id"] || hash[:id],
          type: hash["type"] || hash[:type],
          data: hash["data"] || hash[:data],
          created_at: hash["created_at"] || hash[:created_at]
        )
      end

      # Validate artifact
      def valid?
        return false unless VALID_TYPES.include?(@type)
        return false if @data.nil?
        true
      end
    end
  end
end
