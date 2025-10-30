# frozen_string_literal: true

require "json"

module GitHubDeepResearchAgentV2
  module Util
    # JSONSchema provides validation utilities for JSON structures
    module JSONSchema
      # Validate that a value is a valid JSON object
      def self.valid_json?(str)
        JSON.parse(str)
        true
      rescue JSON::ParserError
        false
      end

      # Validate that a hash has required keys
      def self.has_keys?(hash, *keys)
        return false unless hash.is_a?(Hash)
        keys.all? { |key| hash.key?(key) || hash.key?(key.to_s) }
      end

      # Validate that arrays don't contain duplicates (case-insensitive for strings)
      def self.no_duplicates?(arr)
        return true unless arr.is_a?(Array)
        normalized = arr.map { |item| item.is_a?(String) ? item.downcase.strip : item }
        normalized.uniq.length == normalized.length
      end

      # Extract validation errors from a structure
      def self.extract_errors(obj)
        return [] unless obj.respond_to?(:validation_errors)
        obj.validation_errors
      end
    end
  end
end
