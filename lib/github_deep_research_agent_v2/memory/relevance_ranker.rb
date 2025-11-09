# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "tempfile"
require_relative "../models/fact"

module GitHubDeepResearchAgentV2
  module Memory
    # RelevanceRanker scores and ranks facts by relevance to a query
    class RelevanceRanker
      EMBEDDING_MODEL = "text-embedding-3-small"
      FRESHNESS_DECAY_DAYS = 30

      def initialize(logger: nil)
        @logger = logger
      end

      # Rank facts by relevance to a question
      #
      # @param facts [Array<Models::Fact>] Facts to rank
      # @param question [String] Research question
      # @param top_k [Integer] Number of top facts to return
      # @return [Array<Models::Fact>] Ranked facts
      def rank(facts, question, top_k: 40)
        return facts if facts.empty?
        
        # Score each fact
        scored_facts = facts.map do |fact|
          score = calculate_score(fact, question)
          { fact: fact, score: score }
        end

        # Sort by score descending and return top_k
        scored_facts
          .sort_by { |sf| -sf[:score] }
          .take(top_k)
          .map { |sf| sf[:fact] }
      end

      private

      # Calculate relevance score for a fact
      def calculate_score(fact, question)
        # For now, use simple heuristics (can be enhanced with embeddings)
        semantic_score = simple_semantic_similarity(fact.text, question)
        freshness_score = freshness_decay(fact.extracted_at)
        confidence_score = fact.confidence

        # Weighted combination
        (semantic_score * 0.5) + (freshness_score * 0.2) + (confidence_score * 0.3)
      end

      # Simple semantic similarity based on keyword overlap
      def simple_semantic_similarity(text, query)
        return 0.0 if text.nil? || query.nil?

        text_words = text.downcase.split(/\W+/).reject { |w| w.length < 3 }
        query_words = query.downcase.split(/\W+/).reject { |w| w.length < 3 }

        return 0.0 if query_words.empty?

        overlap = (text_words & query_words).length
        overlap.to_f / query_words.length
      end

      # Calculate freshness decay score
      def freshness_decay(extracted_at)
        return 0.5 if extracted_at.nil?

        begin
          extracted_time = Time.parse(extracted_at)
          days_old = (Time.now.utc - extracted_time) / (24 * 60 * 60)
          
          # Exponential decay
          Math.exp(-days_old / FRESHNESS_DECAY_DAYS)
        rescue
          0.5 # Default score if parsing fails
        end
      end

      # Calculate semantic similarity using embeddings (optional, for future enhancement)
      def semantic_similarity_with_embeddings(text, query)
        # This would use the llm embed command for more accurate similarity
        # For now, falling back to simple keyword matching
        simple_semantic_similarity(text, query)
      end
    end
  end
end
