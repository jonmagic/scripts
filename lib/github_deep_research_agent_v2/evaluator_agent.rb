# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "tempfile"
require_relative "models/evaluation"

module GitHubDeepResearchAgentV2
  # EvaluatorAgent assesses research progress
  class EvaluatorAgent
    def initialize(logger: nil)
      @logger = logger
    end

    # Evaluate research progress
    #
    # @param question [String] Original research question
    # @param plan [Models::Plan] Research plan
    # @param facts [Array<Models::Fact>] Gathered facts
    # @param sources [Array<String>] Unique source URLs
    # @param model [String] LLM model to use
    # @return [Models::Evaluation] Evaluation results
    def evaluate(question, plan, facts, sources, model: nil)
      @logger&.info("Evaluating research progress...")

      # Prepare evaluation prompt
      evaluation_json = call_evaluator_llm(question, plan, facts, sources, model)
      
      # Parse response
      eval_data = JSON.parse(evaluation_json)
      
      # Create evaluation object
      evaluation = Models::Evaluation.new(
        coverage_score: eval_data["coverage_score"] || 0.0,
        confidence_score: eval_data["confidence_score"] || 0.0,
        source_diversity: eval_data["source_diversity"] || 0.0,
        aspect_completion: eval_data["aspect_completion"] || 0.0,
        missing_aspects: eval_data["missing_aspects"] || [],
        notes: eval_data["notes"] || []
      )

      unless evaluation.valid?
        @logger&.warn("Invalid evaluation generated")
      end

      @logger&.info("Evaluation: coverage=#{evaluation.coverage_score}, confidence=#{evaluation.confidence_score}")

      evaluation
    rescue JSON::ParserError => e
      @logger&.error("Failed to parse evaluation JSON: #{e.message}")
      # Return conservative evaluation
      Models::Evaluation.new(
        coverage_score: 0.5,
        confidence_score: 0.5,
        source_diversity: 0.5,
        aspect_completion: 0.5
      )
    rescue => e
      @logger&.error("Evaluation error: #{e.message}")
      Models::Evaluation.new(
        coverage_score: 0.5,
        confidence_score: 0.5,
        source_diversity: 0.5,
        aspect_completion: 0.5
      )
    end

    private

    # Call LLM to evaluate progress
    def call_evaluator_llm(question, plan, facts, sources, model)
      template = File.read(File.join(__dir__, "prompts/evaluator_prompt.txt"))
      
      # Format aspects
      aspects_text = plan.aspects.map do |aspect|
        "- #{aspect['id']}: #{aspect['title']}"
      end.join("\n")

      # Format facts (limit to prevent context overflow)
      max_facts_display = 50
      facts_text = facts.take(max_facts_display).map do |fact|
        "- [#{fact.aspect_id}] #{fact.text[0..200]}#{fact.text.length > 200 ? '...' : ''}"
      end.join("\n")
      
      if facts.length > max_facts_display
        facts_text += "\n... and #{facts.length - max_facts_display} more facts"
      end

      # Calculate repo diversity
      repos = sources.map { |url| extract_repo(url) }.compact.uniq
      
      # Fill template
      prompt = template
        .gsub("{{QUESTION}}", question)
        .gsub("{{ASPECTS}}", aspects_text)
        .gsub("{{FACTS}}", facts_text)
        .gsub("{{SOURCE_COUNT}}", sources.length.to_s)
        .gsub("{{REPO_COUNT}}", repos.length.to_s)

      # Call LLM
      call_llm(prompt, model)
    end

    # Extract repository from GitHub URL
    def extract_repo(url)
      match = url.match(%r{github\.com/([^/]+/[^/]+)})
      match ? match[1] : nil
    end

    # Execute LLM call
    def call_llm(prompt, model = nil)
      check_dependency("llm")
      
      model_flag = model ? "-m #{Shellwords.escape(model)}" : ""

      Tempfile.create(["evaluator_prompt", ".txt"]) do |tmpfile|
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
