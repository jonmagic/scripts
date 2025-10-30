# frozen_string_literal: true

require_relative "../models/fact"

module GitHubDeepResearchAgentV2
  module Memory
    # Compaction handles context size reduction through fact summarization
    class Compaction
      COMPACTION_THRESHOLD = 8000  # Token threshold for compaction

      def initialize(logger: nil)
        @logger = logger
      end

      # Check if compaction is needed based on token count
      def needs_compaction?(facts)
        total_tokens = facts.sum { |f| f.respond_to?(:token_count) ? f.token_count : 0 }
        total_tokens > COMPACTION_THRESHOLD
      end

      # Compact facts by grouping by aspect and summarizing
      #
      # @param facts [Array<Models::Fact>] Facts to compact
      # @return [Array<Models::Fact>] Compacted facts
      def compact(facts)
        return facts unless needs_compaction?(facts)

        @logger&.info("Compacting #{facts.length} facts...")

        # Group facts by aspect_id
        grouped = facts.group_by { |f| f.aspect_id || "general" }

        compacted = []
        grouped.each do |aspect_id, aspect_facts|
          if aspect_facts.length <= 3
            # Keep small groups as-is
            compacted.concat(aspect_facts)
          else
            # Keep top facts by confidence, summarize rest
            sorted = aspect_facts.sort_by { |f| -f.confidence }
            compacted.concat(sorted.take(3))
            
            # Create summary fact for remaining
            remaining = sorted.drop(3)
            if remaining.any?
              summary_text = "Summary of #{remaining.length} additional facts: " +
                             remaining.map { |f| f.text[0..100] }.join("; ")
              summary_urls = remaining.flat_map(&:source_urls).uniq
              
              summary_fact = Models::Fact.new(
                text: summary_text,
                source_urls: summary_urls,
                aspect_id: aspect_id,
                confidence: remaining.map(&:confidence).sum / remaining.length
              )
              compacted << summary_fact
            end
          end
        end

        @logger&.info("Compacted to #{compacted.length} facts")
        compacted
      end
    end
  end
end
