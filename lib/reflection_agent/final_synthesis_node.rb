module ReflectionAgent
  # FinalSynthesisNode - Generates the final reflection document
  #
  # This node:
  # 1. Loads all cluster summaries (snippets + conversations)
  # 2. Selects top 2-3 original snippets for grounding
  # 3. Combines everything into ~20-25KB context
  # 4. Uses LLM to generate comprehensive, structured reflection
  #
  # @example
  #   node = FinalSynthesisNode.new
  #   context = node.prep(shared)
  #   reflection = node.exec(context)
  #   node.post(shared, context, reflection)
  class FinalSynthesisNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Load all summaries and prepare synthesis context
    #
    # @param shared [Hash] Workflow context
    # @return [Hash] All data (or nil if skipping)
    def prep(shared)
      @shared = shared
      @skip_execution = false  # Initialize flag
      logger.info "=== STAGE 6: FINAL SYNTHESIS ==="

      # Check if stage already completed
      output_path = File.join(shared[:reflection_dir], "final-reflection.md")
      if File.exist?(output_path)
        logger.info "Stage 6 already completed, loading existing reflection..."
        existing_reflection = File.read(output_path)

        # Validate that reflection isn't corrupted (empty or too short)
        if existing_reflection.nil? || existing_reflection.strip.empty? || existing_reflection.length < 100
          logger.warn "Existing reflection is corrupted or too short, will regenerate..."
          File.delete(output_path)
          # Continue to normal processing (flag already false)
        else
          @skip_execution = true
          @existing_reflection = existing_reflection
          return nil  # Signal to skip execution
        end
      end

      # Load metadata
      metadata_path = File.join(shared[:reflection_dir], "00-session-metadata.json")
      metadata = JSON.parse(File.read(metadata_path))

      # Load cluster snippet summaries
      snippet_summaries_path = File.join(shared[:reflection_dir], "03-cluster-snippet-summaries.json")
      snippet_summaries = JSON.parse(File.read(snippet_summaries_path))

      # Load cluster conversation summaries
      conversation_summaries_path = File.join(shared[:reflection_dir], "05-cluster-conversation-summaries.json")
      conversation_summaries = JSON.parse(File.read(conversation_summaries_path))

      # Load original snippets for grounding
      snippets_path = File.join(shared[:reflection_dir], "01-snippets.json")
      all_snippets = JSON.parse(File.read(snippets_path))

      # Select top 2-3 snippets (most recent and longest)
      selected_snippets = all_snippets
        .sort_by { |s| [s["end_date"], -s["content"].length] }
        .reverse
        .take(3)

      logger.info "Loaded #{snippet_summaries.length} cluster summaries"
      logger.info "Selected #{selected_snippets.length} snippets for grounding"
      logger.info ""

      {
        metadata: metadata,
        snippet_summaries: snippet_summaries,
        conversation_summaries: conversation_summaries,
        selected_snippets: selected_snippets
      }
    end

    # Generate final reflection document
    #
    # @param context [Hash] All summaries and metadata (or nil if skipping)
    # @return [String] Final reflection markdown (or nil if skipping)
    def exec(context)
      return nil if @skip_execution

      logger.info "Generating final reflection document..."

      # Build cluster summaries section
      cluster_sections = context[:snippet_summaries].map do |ss|
        conv_summary = context[:conversation_summaries].find { |cs| cs["cluster_id"] == ss["cluster_id"] }

        <<~SECTION
          ### #{ss["cluster_name"]}

          #### From Weekly Snippets
          #{ss["summary"]}
          #### From GitHub Conversations
          #{conv_summary ? conv_summary["summary"] : "No conversations found for this cluster."}
        SECTION
      end.join("\n---\n\n")

      # Build selected snippets section
      snippets_text = context[:selected_snippets].map.with_index do |snippet, idx|
        <<~SNIPPET
          #### Snippet #{idx + 1}: #{snippet["start_date"]} to #{snippet["end_date"]}
          #{snippet["content"]}
        SNIPPET
      end.join("\n---\n\n")

      # Generate LLM prompt
      prompt = Utils.fill_template(FINAL_SYNTHESIS_PROMPT, {
        start_date: context[:metadata]["start_date"],
        end_date: context[:metadata]["end_date"],
        purpose: context[:metadata]["purpose"],
        cluster_count: context[:snippet_summaries].length,
        cluster_summaries: cluster_sections,
        selected_snippets: snippets_text
      })

      # Call LLM (Utils.call_llm only accepts positional args: prompt, model)
      reflection = Utils.call_llm(prompt, @shared[:llm_model])

      logger.info "✓ Generated reflection (#{reflection.length} chars)"
      logger.info ""

      reflection
    end

    # Write final reflection to disk
    #
    # @param shared [Hash] Workflow context
    # @param prep_res [Hash] Context from prep
    # @param exec_res [String] Final reflection
    # @return [nil]
    def post(shared, prep_res, exec_res)
      # Use stored shared context (handles case where shared param might be nil)
      ctx = shared || @shared

      # If we skipped execution, use existing reflection
      reflection_text = @skip_execution ? @existing_reflection : exec_res

      # Write final reflection (only if we didn't skip)
      output_path = File.join(ctx[:reflection_dir], "final-reflection.md")
      unless @skip_execution
        File.write(output_path, reflection_text)
        logger.info "Wrote final reflection: #{output_path}"
      end

      # Write ledger
      ledger = {
        stage: "final_synthesis",
        status: @skip_execution ? "resumed" : "completed",
        reflection_length: reflection_text.length,
        output_file: output_path,
        next: "end",
        createdAt: Time.now.utc.iso8601
      }
      ledger_path = File.join(ctx[:reflection_dir], "stage-6-final-synthesis.ledger.json")
      File.write(ledger_path, JSON.pretty_generate(ledger))

      logger.info ""
      if @skip_execution
        logger.info "✓ Stage 6 resumed: Loaded existing final reflection"
      else
        logger.info "✓ Stage 6 complete: Final reflection generated"
      end
      logger.info "  Output: #{output_path}"
      logger.info ""

      nil
    end

    # LLM prompt for final synthesis
    FINAL_SYNTHESIS_PROMPT = <<~PROMPT
      You are creating a comprehensive personal work reflection for the period from {{start_date}} to {{end_date}}.

      ## PURPOSE
      {{purpose}}

      ## CLUSTER SUMMARIES ({{cluster_count}} total)

      The work has been organized into {{cluster_count}} temporal clusters. Each cluster includes:
      - Themes and accomplishments from weekly snippets (curated highlights)
      - Key GitHub conversations (issues, PRs, discussions) that were referenced

      {{cluster_summaries}}

      ## SELECTED ORIGINAL SNIPPETS

      For additional context and grounding, here are some of the original weekly snippets:

      {{selected_snippets}}

      ## YOUR TASK

      Create a comprehensive, well-structured reflection document that synthesizes all of this information.
      Use the following structure:

      ### 1. Executive Summary (3-4 paragraphs)
      - High-level overview of the entire period
      - Major themes and accomplishments
      - Key transitions or shifts in focus
      - Overall narrative arc

      ### 2. Timeline & Phases
      - Break the period into logical phases or themes
      - For each phase: main focus areas, key outcomes, notable challenges
      - Use the cluster summaries to identify natural divisions

      ### 3. Technical Deep Dives (3-5 sections)
      - Pick the 3-5 most significant technical areas
      - For each: what was built/learned, key decisions, outcomes
      - Include specific GitHub conversations where relevant
      - Be technical and specific - use actual feature names, technologies, etc.

      ### 4. Collaboration & Impact
      - Key collaborations and partnerships
      - Cross-team or cross-domain work
      - Impact on others or broader organization
      - Mentorship or knowledge sharing

      ### 5. Patterns & Insights
      - What patterns emerge across the clusters?
      - What worked well? What was challenging?
      - Key learnings or shifts in thinking
      - Connections between different work streams

      ### 6. Looking Forward
      - Open threads or unfinished work
      - Emerging themes or areas of interest
      - Questions or areas for future exploration

      ## GUIDELINES
      - Be specific and technical - this is for your own reference
      - Use bullet points and structured sections for readability
      - Include relevant GitHub URLs when referencing specific work
      - Aim for 2000-3000 words total
      - Write in first person ("I worked on...", "We built...")
      - Focus on substance over style - clarity and completeness matter most
    PROMPT
  end
end
