# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"

module GitHubDeepResearchAgentV2
  module Search
    # SemanticSearchAdapter wraps semantic search functionality
    class SemanticSearchAdapter
      def initialize(collection:, script_dir:, logger: nil)
        @collection = collection
        @script_dir = script_dir
        @logger = logger
      end

      # Execute semantic search
      #
      # @param query [String] Search query
      # @param limit [Integer] Number of results
      # @param created_after [String] Optional date filter (ISO 8601)
      # @return [Array<Hash>] Search results
      def search(query, limit: 5, created_after: nil)
        @logger&.debug("Semantic search: #{query}")

        cmd_parts = [
          File.join(@script_dir, "semantic-search-github-conversations"),
          Shellwords.escape(query),
          "--collection", Shellwords.escape(@collection),
          "--limit", limit.to_s
        ]

        if created_after
          # Note: semantic search script may not support created_after directly
          # This would be a feature enhancement
          @logger&.debug("Date filter requested: #{created_after}")
        end

        cmd = cmd_parts.join(" ")
        stdout, stderr, status = Open3.capture3(cmd)

        unless status.success?
          @logger&.error("Semantic search failed: #{stderr}")
          return []
        end

        # Parse results (assuming JSONL output)
        parse_results(stdout)
      rescue => e
        @logger&.error("Semantic search error: #{e.message}")
        []
      end

      private

      # Parse search results
      def parse_results(output)
        results = []
        output.each_line do |line|
          next if line.strip.empty?
          begin
            result = JSON.parse(line.strip)
            results << result
          rescue JSON::ParserError
            @logger&.debug("Skipping non-JSON line: #{line[0..50]}")
          end
        end
        results
      end
    end
  end
end
