# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "tempfile"
require_relative "models/summary"
require_relative "models/fact"

module GitHubDeepResearchAgentV2
  # SummarizerAgent extracts facts from conversation text
  class SummarizerAgent
    MIN_FACTS = 3
    MAX_FACTS = 8

    def initialize(logger: nil)
      @logger = logger
    end

    # Summarize a conversation into facts
    #
    # @param conversation [Hash] Conversation data with title, url, body
    # @param model [String] LLM model to use
    # @return [Models::Summary] Extracted summary with facts
    def summarize(conversation, model: nil)
      title = conversation[:title] || conversation["title"] || ""
      url = conversation[:url] || conversation["url"] || ""
      body = conversation[:body] || conversation["body"] || ""

      @logger&.debug("Summarizing: #{title}")

      summary_json = call_summarizer_llm(title, url, body, model)
      
      # Parse response
      summary_data = JSON.parse(summary_json)
      
      # Create summary object
      summary = Models::Summary.new(
        source_url: url,
        facts: summary_data["facts"] || [],
        topics: summary_data["topics"] || [],
        confidence: summary_data["confidence"] || 0.5
      )

      # Validate
      unless summary.valid?
        @logger&.warn("Invalid summary generated for #{url}")
      end

      summary
    rescue JSON::ParserError => e
      @logger&.error("Failed to parse summary JSON: #{e.message}")
      # Return minimal summary
      Models::Summary.new(source_url: url, facts: [], topics: [], confidence: 0.0)
    rescue => e
      @logger&.error("Summarization error: #{e.message}")
      Models::Summary.new(source_url: url, facts: [], topics: [], confidence: 0.0)
    end

    # Convert summary to facts
    #
    # @param summary [Models::Summary] Summary object
    # @param aspect_id [String] Aspect ID for facts
    # @return [Array<Models::Fact>] Array of fact objects
    def summary_to_facts(summary, aspect_id: nil)
      facts = []
      
      summary.facts.each do |fact_text|
        fact = Models::Fact.new(
          text: fact_text,
          source_urls: [summary.source_url],
          aspect_id: aspect_id,
          confidence: summary.confidence
        )
        facts << fact if fact.valid?
      end

      facts
    end

    private

    # Call LLM to extract facts
    def call_summarizer_llm(title, url, body, model)
      template = File.read(File.join(__dir__, "prompts/summarizer_prompt.txt"))
      
      # Truncate body if too long (rough limit to avoid context issues)
      max_body_length = 10_000
      truncated_body = if body.length > max_body_length
        body[0..max_body_length] + "\n\n[TRUNCATED]"
      else
        body
      end

      # Fill template
      prompt = template
        .gsub("{{TITLE}}", title)
        .gsub("{{URL}}", url)
        .gsub("{{BODY}}", truncated_body)

      # Call LLM
      call_llm(prompt, model)
    end

    # Execute LLM call
    def call_llm(prompt, model = nil)
      check_dependency("llm")
      
      model_flag = model ? "-m #{Shellwords.escape(model)}" : ""

      Tempfile.create(["summarizer_prompt", ".txt"]) do |tmpfile|
        tmpfile.write(prompt)
        tmpfile.flush
        
        cmd = "llm #{model_flag} < #{Shellwords.escape(tmpfile.path)}"
        stdout, stderr, status = Open3.capture3(cmd)
        
        unless status.success?
          raise "LLM call failed: #{stderr}"
        end

        stdout.strip
      end
    end

    # Check if command exists
    def check_dependency(cmd)
      unless system("which #{cmd} > /dev/null 2>&1")
        raise "Required dependency '#{cmd}' not found in PATH"
      end
    end
  end
end
