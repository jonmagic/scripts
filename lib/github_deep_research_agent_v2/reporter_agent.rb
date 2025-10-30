# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "tempfile"

module GitHubDeepResearchAgentV2
  # ReporterAgent synthesizes findings into final Markdown report
  class ReporterAgent
    def initialize(logger: nil)
      @logger = logger
    end

    # Generate final research report
    #
    # @param question [String] Original research question
    # @param plan [Models::Plan] Research plan
    # @param facts [Array<Models::Fact>] Gathered facts
    # @param sources [Array<String>] Unique source URLs
    # @param gaps [Array<String>] Remaining gaps in research
    # @param methodology [Hash] Methodology information
    # @param model [String] LLM model to use
    # @return [String] Markdown report
    def generate_report(question, plan, facts, sources, gaps: [], methodology: {}, model: nil)
      @logger&.info("Generating final research report...")

      report_md = call_reporter_llm(question, plan, facts, sources, gaps, methodology, model)
      
      @logger&.info("Report generated successfully (#{report_md.length} characters)")
      
      report_md
    rescue => e
      @logger&.error("Report generation error: #{e.message}")
      generate_fallback_report(question, facts, sources, e.message)
    end

    private

    # Call LLM to generate report
    def call_reporter_llm(question, plan, facts, sources, gaps, methodology, model)
      template = File.read(File.join(__dir__, "prompts/reporter_prompt.txt"))
      
      # Format facts by aspect
      facts_by_aspect = facts.group_by { |f| f.aspect_id }
      facts_text = ""
      
      plan.aspects.each do |aspect|
        aspect_id = aspect["id"]
        aspect_facts = facts_by_aspect[aspect_id] || []
        
        facts_text += "\n### #{aspect['title']} (#{aspect_id})\n"
        aspect_facts.each do |fact|
          facts_text += "- #{fact.text}\n"
        end
      end

      # Format sources with IDs
      sources_text = sources.each_with_index.map do |url, i|
        "S#{i + 1}: #{url}"
      end.join("\n")

      # Format success criteria
      criteria_text = (plan.success_criteria || []).map { |c| "- #{c}" }.join("\n")

      # Format gaps
      gaps_text = gaps.empty? ? "None identified" : gaps.map { |g| "- #{g}" }.join("\n")

      # Format methodology
      method_text = format_methodology(methodology)

      # Fill template
      prompt = template
        .gsub("{{QUESTION}}", question)
        .gsub("{{FACTS}}", facts_text)
        .gsub("{{SOURCES}}", sources_text)
        .gsub("{{SUCCESS_CRITERIA}}", criteria_text)
        .gsub("{{GAPS}}", gaps_text)
        .gsub("{{METHODOLOGY}}", method_text)

      # Call LLM
      call_llm(prompt, model)
    end

    # Format methodology information
    def format_methodology(methodology)
      text = ""
      text += "Depth reached: #{methodology[:depth_reached] || 'N/A'}\n"
      text += "Breadth: #{methodology[:breadth] || 'N/A'} aspects\n"
      
      if methodology[:token_usage]
        usage = methodology[:token_usage]
        text += "Token usage: "
        text += "planning=#{usage[:planning] || 0}, "
        text += "research=#{usage[:research] || 0}, "
        text += "summarization=#{usage[:summarization] || 0}, "
        text += "report=#{usage[:report] || 0}\n"
      end
      
      text += "Budget status: #{methodology[:budget_status] || 'N/A'}\n"
      text
    end

    # Generate fallback report if LLM call fails
    def generate_fallback_report(question, facts, sources, error)
      report = "# Research Report\n\n"
      report += "## Question\n#{question}\n\n"
      report += "## Error\nReport generation encountered an error: #{error}\n\n"
      report += "## Gathered Facts (#{facts.length})\n"
      
      facts.take(20).each do |fact|
        report += "- #{fact.text}\n"
      end
      
      if facts.length > 20
        report += "\n... and #{facts.length - 20} more facts\n"
      end
      
      report += "\n## Sources (#{sources.length})\n"
      sources.take(10).each_with_index do |url, i|
        report += "#{i + 1}. #{url}\n"
      end
      
      if sources.length > 10
        report += "\n... and #{sources.length - 10} more sources\n"
      end
      
      report
    end

    # Execute LLM call
    def call_llm(prompt, model = nil)
      check_dependency("llm")
      
      model_flag = model ? "-m #{Shellwords.escape(model)}" : ""

      Tempfile.create(["reporter_prompt", ".txt"]) do |tmpfile|
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
