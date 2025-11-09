# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "tempfile"
require_relative "models/plan"
require_relative "plan_verifier"
require_relative "util/retry"

module GitHubDeepResearchAgentV2
  # Planner generates structured research plans
  class Planner
    MAX_PLAN_ATTEMPTS = 3

    def initialize(logger: nil, max_aspects: 8, breadth_limit: 5)
      @logger = logger
      @max_aspects = max_aspects
      @breadth_limit = breadth_limit
      @verifier = PlanVerifier.new(logger: logger)
    end

    # Generate a research plan for a question
    #
    # @param question [String] Research question
    # @param prior_knowledge [String] Any prior knowledge or context
    # @param model [String] LLM model to use
    # @return [Models::Plan] Generated and verified plan
    def generate_plan(question, prior_knowledge: "", model: nil)
      @logger&.info("Generating research plan...")

      attempt = 1
      last_errors = []

      MAX_PLAN_ATTEMPTS.times do
        @logger&.debug("Plan generation attempt #{attempt}/#{MAX_PLAN_ATTEMPTS}")

        plan_json = call_planner_llm(question, prior_knowledge, last_errors, model)
        
        # Verify the plan
        result = @verifier.verify(plan_json)

        if result[:valid]
          @logger&.info("Plan generated successfully")
          return result[:plan]
        else
          @logger&.warn("Plan validation failed: #{result[:errors].join(', ')}")
          last_errors = result[:errors]
          attempt += 1
        end
      end

      raise "Failed to generate valid plan after #{MAX_PLAN_ATTEMPTS} attempts. Last errors: #{last_errors.join(', ')}"
    end

    private

    # Call LLM to generate plan
    def call_planner_llm(question, prior_knowledge, previous_errors, model)
      template = File.read(File.join(__dir__, "prompts/planner_prompt.txt"))
      
      # Build prior knowledge section
      prior_text = if prior_knowledge.empty?
        "None"
      else
        prior_knowledge
      end

      # Add previous errors if any
      if previous_errors.any?
        prior_text += "\n\n<PREVIOUS_ERRORS>\n"
        prior_text += "The previous plan had these errors:\n"
        prior_text += previous_errors.map { |e| "- #{e}" }.join("\n")
        prior_text += "\nPlease revise the plan to address these issues.\n"
        prior_text += "</PREVIOUS_ERRORS>"
      end

      # Fill template
      prompt = template
        .gsub("{{QUESTION}}", question)
        .gsub("{{PRIOR_KNOWLEDGE}}", prior_text)
        .gsub("{{MAX_ASPECTS}}", @max_aspects.to_s)
        .gsub("{{BREADTH_LIMIT}}", @breadth_limit.to_s)

      # Call LLM
      call_llm(prompt, model)
    end

    # Execute LLM call
    def call_llm(prompt, model = nil)
      check_dependency("llm")
      
      model_flag = model ? "-m #{Shellwords.escape(model)}" : ""

      Tempfile.create(["planner_prompt", ".txt"]) do |tmpfile|
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
