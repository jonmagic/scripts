# lib/github_deep_research_agent/ask_clarifying_node.rb
#
# AskClarifyingNode: Generates clarifying questions based on initial research findings and collects user input.

require_relative "../pocketflow"
require_relative "../utils"

module GitHubDeepResearchAgent
  # AskClarifyingNode: Generates clarifying questions based on initial research findings and collects user input.
  #
  # This node:
  # - Uses LLM to generate clarifying questions based on research request and initial findings
  # - Opens an editor for user to provide answers (or uses pre-written Q&A file)
  # - Stores clarifications in shared context for later nodes to use
  #
  # The generated questions help focus the research by understanding:
  # - Intent and scope of the request
  # - Specific search spaces (repos, organizations)
  # - Expected output format (summary, analysis, ADR, etc.)
  class AskClarifyingNode < Pocketflow::Node
    def prep(shared)
      @shared = shared # Store shared context
      LOG.info "=== CLARIFYING QUESTIONS PHASE ==="
      LOG.info "Generating clarifying questions based on initial findings..."

      # Summarize initial findings
      initial_findings = shared[:memory][:hits].map do |hit|
        "- #{hit[:url]}: #{hit[:summary]}"
      end.join("\n")

      LOG.debug do
        "Initial findings summary:\n#{initial_findings}"
      end

      # Fill template and call LLM
      prompt = Utils.fill_template(ASK_CLARIFY_PROMPT, {
        request: shared[:request],
        initial_findings: initial_findings
      })

      LOG.debug "Calling LLM to generate clarifying questions..."
      # Use fast model for clarifying questions - this is light reasoning to generate questions based on initial findings
      llm_response = Utils.call_llm(prompt, shared[:models][:fast])

      LOG.info "Generated clarifying questions for user review"
      LOG.debug do
        "Generated questions:\n#{'=' * 60}\n#{llm_response}\n#{'=' * 60}"
      end

      llm_response
    end

    def exec(clarifying_questions)
      # Check if we have a pre-written Q&A file to bypass interactive step
      if @shared[:clarifying_qa]
        LOG.info "Using pre-written clarifying Q&A from file: #{@shared[:clarifying_qa]}"

        unless File.exist?(@shared[:clarifying_qa])
          abort "Error: Clarifying Q&A file not found: #{@shared[:clarifying_qa]}"
        end

        edited_content = File.read(@shared[:clarifying_qa])
        LOG.debug do
          "Pre-written clarifications:\n#{'=' * 60}\n#{edited_content}\n#{'=' * 60}"
        end

        return edited_content
      end

      LOG.info "Opening editor for user to answer clarifying questions..."

      # Prepare editor content
      editor_content = <<~CONTENT
Please review the following questions and provide inline answers to help focus the research:

#{clarifying_questions}
CONTENT

      # Open editor
      edited_content = Utils.edit_text(editor_content, @shared[:editor_file])

      LOG.info "User provided clarifications"
      LOG.debug do
        "User clarifications:\n#{'=' * 60}\n#{edited_content}\n#{'=' * 60}"
      end

      edited_content
    end

    def post(shared, prep_res, exec_res)
      shared[:clarifications] = exec_res
      LOG.info "✓ Clarifications collected, proceeding to planning phase"
      LOG.debug "Moving to planning phase..."

      nil
    end

    # Embedded prompt template
    ASK_CLARIFY_PROMPT = <<~PROMPT
You are an expert analyst reviewing a research request and initial findings from GitHub conversations.

## Research Request
{{request}}

## Initial Findings Summary
{{initial_findings}}

Based on the question and initial findings, generate up to 4 clarifying questions that would help you better understand the intent of the request, bridge gaps in context to better refine the search (e.g. specifying the search space like a github organization or repository), and understand the expected output format (executive summary, detailed analysis, ADR, etc). If any of these areas are covered in their request or initial findings, do not ask about them.

Format your response as a numbered list with clear, specific questions. Each question should be on its own line starting with a number. The instructions should ask for inline answers to these questions.
PROMPT
  end
end
