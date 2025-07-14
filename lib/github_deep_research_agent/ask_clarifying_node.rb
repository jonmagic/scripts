module GitHubDeepResearchAgent
  # AskClarifyingNode - Generates and collects clarifying questions to refine research focus
  #
  # See lib/github_deep_research_agent.rb for architecture and workflow details.
  #
  # ## Overview
  # After initial search, this node uses an LLM to generate up to 4 clarifying questions
  # that help specify research intent, scope, output format, and fill context gaps.
  # User answers are collected (via editor or file) and stored for downstream nodes.
  #
  # ## Pipeline Position
  # - Input: Initial research findings, user request
  # - Output: User clarifications for PlannerNode and others
  #
  # @example
  #   node = AskClarifyingNode.new
  #   questions = node.prep(shared)
  #   answers = node.exec(questions)
  #   node.post(shared, questions, answers)
  class AskClarifyingNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Generate up to 4 clarifying questions using LLM, based on initial findings and user request.
    #
    # @param shared [Hash] Workflow context with :memory, :request, :models
    # @return [String] Numbered list of clarifying questions
    def prep(shared)
      @shared = shared # Store shared context for use in other methods
      logger.info "=== CLARIFYING QUESTIONS PHASE ==="
      logger.info "Generating clarifying questions based on initial findings..."

      # Extract and format initial findings from the shared memory
      # Each hit contains: {url: String, summary: String, other_metadata...}
      initial_findings = shared[:memory][:hits].map do |hit|
        "- #{hit[:url]}: #{hit[:summary]}"
      end.join("\n")

      logger.debug do
        "Initial findings summary:\n#{initial_findings}"
      end

      # Fill the prompt template with current context
      # This creates a structured prompt that gives the LLM both the user's
      # original request and what we've already discovered
      prompt = Utils.fill_template(ASK_CLARIFY_PROMPT, {
        request: shared[:request],
        initial_findings: initial_findings
      })

      logger.debug "Calling LLM to generate clarifying questions..."
      # Use fast model for clarifying questions - this is light reasoning to generate
      # questions based on initial findings, not heavy analysis
      llm_response = Utils.call_llm(prompt, shared[:models][:fast])

      logger.info "Generated clarifying questions for user review"
      logger.debug do
        "Generated questions:\n#{'=' * 60}\n#{llm_response}\n#{'=' * 60}"
      end

      llm_response
    end

    # Collect user responses to clarifying questions (from file or editor).
    #
    # @param clarifying_questions [String] Questions from prep()
    # @return [String] User responses (inline answers)
    def exec(clarifying_questions)
      # Branch 1: Use pre-written Q&A file (for automation/testing)
      if @shared[:clarifying_qa]
        logger.info "Using pre-written clarifying Q&A from file: #{@shared[:clarifying_qa]}"

        # Validate file existence before attempting to read
        unless File.exist?(@shared[:clarifying_qa])
          abort "Error: Clarifying Q&A file not found: #{@shared[:clarifying_qa]}"
        end

        edited_content = File.read(@shared[:clarifying_qa])
        logger.debug do
          "Pre-written clarifications:\n#{'=' * 60}\n#{edited_content}\n#{'=' * 60}"
        end

        return edited_content
      end

      # Branch 2: Interactive editor session for user input
      logger.info "Opening editor for user to answer clarifying questions..."

      # Prepare editor content with instructions and questions
      # The format provides clear guidance on what the user should do
      editor_content = <<~CONTENT
Please review the following questions and provide inline answers to help focus the research:

#{clarifying_questions}
CONTENT

      # Open text editor and collect user input
      # Utils.edit_text handles temporary file creation, editor launching, and cleanup
      edited_content = Utils.edit_text(editor_content, @shared[:editor_file])

      logger.info "User provided clarifications"
      logger.debug do
        "User clarifications:\n#{'=' * 60}\n#{edited_content}\n#{'=' * 60}"
      end

      edited_content
    end

    # Store clarifications in shared context for downstream nodes.
    #
    # @param shared [Hash] Workflow context to update
    # @param prep_res [String] Questions from prep()
    # @param exec_res [String] User responses from exec()
    # @return [nil]
    def post(shared, prep_res, exec_res)
      # Store user clarifications in shared context for downstream nodes
      shared[:clarifications] = exec_res
      logger.info "✓ Clarifications collected, proceeding to planning phase"
      logger.debug "Moving to planning phase..."

      # Return nil to indicate completion without additional data flow
      nil
    end

    # Prompt for generating clarifying questions (see prep for usage)
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
