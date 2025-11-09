# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"

module GitHubDeepResearchAgentV2
  module Search
    # KeywordSearchAdapter wraps keyword search functionality
    class KeywordSearchAdapter
      def initialize(script_dir:, logger: nil)
        @script_dir = script_dir
        @logger = logger
      end

      # Execute keyword search using GitHub search syntax
      #
      # @param query [String] GitHub search query (e.g., "repo:owner/repo is:issue")
      # @param limit [Integer] Number of results
      # @return [Array<Hash>] Search results
      def search(query, limit: 5)
        @logger&.debug("Keyword search: #{query}")

        cmd_parts = [
          File.join(@script_dir, "search-github-conversations"),
          Shellwords.escape(query),
          "--limit", limit.to_s
        ]

        cmd = cmd_parts.join(" ")
        stdout, stderr, status = Open3.capture3(cmd)

        unless status.success?
          @logger&.error("Keyword search failed: #{stderr}")
          return []
        end

        # Parse results (assuming JSONL output)
        parse_results(stdout)
      rescue => e
        @logger&.error("Keyword search error: #{e.message}")
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
