# frozen_string_literal: true

require_relative "search/semantic_search_adapter"
require_relative "search/keyword_search_adapter"
require_relative "summarizer_agent"

module GitHubDeepResearchAgentV2
  # ResearchSubAgent executes search and summarization for one aspect
  class ResearchSubAgent
    def initialize(
      collection:,
      script_dir:,
      logger: nil,
      summarizer: nil,
      cache_path: nil
    )
      @collection = collection
      @script_dir = script_dir
      @logger = logger
      @cache_path = cache_path
      
      # Initialize search adapters
      @semantic_search = Search::SemanticSearchAdapter.new(
        collection: collection,
        script_dir: script_dir,
        logger: logger
      )
      @keyword_search = Search::KeywordSearchAdapter.new(
        script_dir: script_dir,
        logger: logger
      )
      
      # Initialize summarizer
      @summarizer = summarizer || SummarizerAgent.new(logger: logger)
    end

    # Execute research for a query plan
    #
    # @param plan [Hash] Query plan with :tool, :query, and optional filters
    # @param limit [Integer] Max results to retrieve
    # @param aspect_id [String] Aspect ID for fact tagging
    # @param model [String] LLM model for summarization
    # @return [Hash] Results with :raw_results, :summaries, :facts
    def research(plan, limit: 5, aspect_id: nil, model: nil)
      tool = plan[:tool]
      query = plan[:query]
      created_after = plan[:created_after]

      @logger&.info("Researching with #{tool}: #{query}")

      # Execute search
      raw_results = case tool
      when :semantic
        @semantic_search.search(query, limit: limit, created_after: created_after)
      when :keyword
        @keyword_search.search(query, limit: limit)
      else
        @logger&.warn("Unknown search tool: #{tool}")
        []
      end

      @logger&.info("Found #{raw_results.length} results")

      # Fetch and summarize conversations
      summaries = []
      all_facts = []

      raw_results.each do |result|
        conversation = fetch_conversation(result)
        next unless conversation

        # Summarize
        summary = @summarizer.summarize(conversation, model: model)
        summaries << summary

        # Convert to facts
        facts = @summarizer.summary_to_facts(summary, aspect_id: aspect_id)
        all_facts.concat(facts)
      end

      @logger&.info("Extracted #{all_facts.length} facts from #{summaries.length} conversations")

      {
        raw_results: raw_results,
        summaries: summaries,
        facts: all_facts
      }
    rescue => e
      @logger&.error("Research error: #{e.message}")
      @logger&.debug(e.backtrace.join("\n")) if @logger
      {
        raw_results: [],
        summaries: [],
        facts: []
      }
    end

    private

    # Fetch full conversation data
    def fetch_conversation(result)
      url = result["url"] || result[:url]
      return nil unless url

      @logger&.debug("Fetching: #{url}")

      # Use existing fetch script
      cmd = "#{File.join(@script_dir, 'fetch-github-conversation')} #{Shellwords.escape(url)}"
      
      # Add cache path if provided
      if @cache_path
        cmd += " --cache-path #{Shellwords.escape(@cache_path)}"
      end

      stdout, stderr, status = Open3.capture3(cmd)

      unless status.success?
        @logger&.warn("Failed to fetch #{url}: #{stderr}")
        return nil
      end

      JSON.parse(stdout)
    rescue JSON::ParserError => e
      @logger&.error("Failed to parse conversation JSON: #{e.message}")
      nil
    rescue => e
      @logger&.error("Fetch error for #{url}: #{e.message}")
      nil
    end
  end
end
