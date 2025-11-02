module ReflectionAgent
  # ClusterConversationSummaryNode - Summarizes GitHub conversations per cluster
  #
  # This node:
  # 1. Takes cluster-organized conversations from previous stage
  # 2. For each cluster: reads snippet summary + top N conversations
  # 3. Uses LLM to extract conversation themes and patterns
  # 4. Generates bounded summaries (~2KB per cluster) for final synthesis
  #
  # Uses ParallelBatchNode for concurrent cluster processing
  #
  # @example
  #   node = ClusterConversationSummaryNode.new
  #   cluster_data = node.prep(shared)
  #   summaries = node.exec_batch(cluster)
  #   node.post(shared, cluster_data, all_summaries)
  class ClusterConversationSummaryNode < Pocketflow::ParallelBatchNode
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Load cluster data from previous stages
    #
    # @param shared [Hash] Workflow context
    # @return [Array<Hash>] Cluster data (or empty array if skipping)
    def prep(shared)
      @shared = shared
      @skip_execution = false  # Initialize flag
      logger.info "=== STAGE 5: SUMMARIZE CONVERSATIONS PER CLUSTER ==="

      # Check if stage already completed
      output_path = File.join(shared[:reflection_dir], "05-cluster-conversation-summaries.json")
      if File.exist?(output_path)
        logger.info "Stage 5 already completed, loading existing conversation summaries..."
        existing_summaries = JSON.parse(File.read(output_path))

        # Validate that summaries aren't corrupted (all nil values)
        if existing_summaries.all?(&:nil?)
          logger.warn "Existing summaries are corrupted (all nil), will regenerate..."
          File.delete(output_path)
          # Continue to normal processing (flag already false)
        else
          @skip_execution = true
          @existing_summaries = existing_summaries
          return []  # Empty array skips ParallelBatchNode execution
        end
      end

      # Load cluster snippet summaries
      snippet_summaries_path = File.join(shared[:reflection_dir], "03-cluster-snippet-summaries.json")
      snippet_summaries = JSON.parse(File.read(snippet_summaries_path))

      # Load cluster-organized conversations
      conversations_path = File.join(shared[:reflection_dir], "04-conversations-by-cluster.json")
      cluster_conversations = JSON.parse(File.read(conversations_path))

      # Combine data for each cluster
      clusters = snippet_summaries.map do |ss|
        cluster_convs = cluster_conversations.find { |cc| cc["cluster_id"] == ss["cluster_id"] }

        {
          cluster_id: ss["cluster_id"],
          cluster_name: ss["cluster_name"],
          snippet_summary: ss["summary"],
          conversations: cluster_convs ? cluster_convs["conversations"] : [],
          snippet_summary_path: File.join(shared[:reflection_dir], "clusters", "#{ss['cluster_id']}-snippet-summary.md")
        }
      end

      logger.info "Processing #{clusters.length} clusters in parallel"
      logger.info ""

      clusters
    end

    # Summarize conversations for one cluster
    #
    # @param cluster [Hash] Cluster data with snippet summary and conversations
    # @return [Hash] Conversation summary for this cluster
    def exec(cluster)
      # Handle both symbol and string keys
      cluster_id = cluster[:cluster_id] || cluster["cluster_id"]
      cluster_name = cluster[:cluster_name] || cluster["cluster_name"]
      conversations = cluster[:conversations] || cluster["conversations"] || []
      snippet_summary_path = cluster[:snippet_summary_path] || cluster["snippet_summary_path"]

      logger.info "  [Cluster #{cluster_id}] Summarizing conversations..."

      # Filter to only found conversations and take top 20 by order (already scored in loader)
      found_conversations = conversations
        .select { |c| c["found"] }
        .take(20)

      if found_conversations.empty?
        logger.info "  [Cluster #{cluster_id}] No conversations found, skipping"
        return {
          cluster_id: cluster_id,
          cluster_name: cluster_name,
          summary: "No GitHub conversations were referenced in this cluster's snippets.",
          conversation_count: 0
        }
      end

      # Read snippet summary for context
      snippet_summary = File.read(snippet_summary_path)

      # Build conversation context
      conversations_text = found_conversations.map.with_index do |conv, idx|
        "### Conversation #{idx + 1}: #{conv['url']}\n\n#{conv['summary']}"
      end.join("\n\n---\n\n")

      # Generate LLM prompt
      prompt = Utils.fill_template(CLUSTER_CONVERSATION_SUMMARY_PROMPT, {
        cluster_name: cluster_name,
        snippet_summary: snippet_summary,
        conversation_count: found_conversations.length,
        conversations: conversations_text
      })

      # Call LLM (Utils.call_llm only accepts positional args: prompt, model)
      summary = Utils.call_llm(prompt, @shared[:llm_model])

      logger.info "  [Cluster #{cluster_id}] ✓ Generated summary (#{summary.length} chars)"

      {
        cluster_id: cluster_id,
        cluster_name: cluster_name,
        summary: summary,
        conversation_count: found_conversations.length
      }
    end

    # Write all conversation summaries to disk
    #
    # @param shared [Hash] Workflow context
    # @param prep_res [Array<Hash>] Cluster data from prep
    # @param exec_res [Array<Hash>] All conversation summaries
    # @return [nil]
    def post(shared, prep_res, exec_res)
      # Use stored shared context (handles case where shared param might be nil)
      ctx = shared || @shared

      # If we skipped execution, use existing summaries
      summaries = @skip_execution ? @existing_summaries : exec_res

      # Handle nil or empty results
      if summaries.nil? || summaries.empty?
        logger.error "No conversation summaries available"
        return nil
      end

      # Write files only if we didn't skip
      unless @skip_execution
        # Write combined JSON
        output_path = File.join(ctx[:reflection_dir], "05-cluster-conversation-summaries.json")
        File.write(output_path, JSON.pretty_generate(summaries))
        logger.info "Wrote cluster conversation summaries: #{output_path}"

        # Write individual markdown files
        summaries.each do |summary|
          # Skip nil summaries
          if summary.nil?
            logger.warn "Skipping nil summary in post()"
            next
          end

          # Handle both symbol and string keys
          cluster_id = summary[:cluster_id] || summary["cluster_id"]
          summary_text = summary[:summary] || summary["summary"]

          next unless cluster_id && summary_text

          md_path = File.join(
            ctx[:reflection_dir],
            "clusters",
            "#{cluster_id}-conversation-summary.md"
          )
          File.write(md_path, summary_text)
        end
        logger.info "Wrote individual conversation summary files to clusters/"
      end

      # Write ledger
      total_conversations = summaries.sum { |s| s[:conversation_count] || s["conversation_count"] || 0 }
      ledger = {
        stage: "cluster_conversation_summary",
        status: @skip_execution ? "resumed" : "completed",
        cluster_count: summaries.length,
        total_conversations: total_conversations,
        next: "final_synthesis",
        createdAt: Time.now.utc.iso8601
      }
      ledger_path = File.join(ctx[:reflection_dir], "stage-5-cluster-conversation-summary.ledger.json")
      File.write(ledger_path, JSON.pretty_generate(ledger))

      logger.info ""
      if @skip_execution
        logger.info "✓ Stage 5 resumed: Loaded #{total_conversations} existing conversation summaries across #{summaries.length} clusters"
      else
        logger.info "✓ Stage 5 complete: Summarized #{total_conversations} conversations across #{summaries.length} clusters"
      end
      logger.info "  Next: Final synthesis"
      logger.info ""

      nil
    end

    # LLM prompt for summarizing conversations within a cluster
    CLUSTER_CONVERSATION_SUMMARY_PROMPT = <<~PROMPT
      You are analyzing GitHub conversations (issues, PRs, discussions) from a specific time period.

      ## CLUSTER: {{cluster_name}}

      ### Context from Weekly Snippets
      {{snippet_summary}}

      ### GitHub Conversations ({{conversation_count}} total)
      {{conversations}}

      ## YOUR TASK

      Analyze these {{conversation_count}} GitHub conversations and create a structured summary that identifies:

      1. **Technical Themes** (3-5 bullets)
         - What technical topics, technologies, or areas of work are represented?
         - What systems, features, or components were being developed or discussed?

      2. **Key Conversations** (3-7 bullets)
         - Which conversations were most significant or impactful?
         - What were the main outcomes, decisions, or learnings?
         - Include the conversation URL in each bullet

      3. **Collaboration Patterns** (2-4 bullets)
         - Who were the key collaborators or teams involved?
         - What types of interactions happened? (code review, design discussion, debugging, etc.)
         - Any notable cross-team or cross-domain work?

      4. **Connections to Snippets** (2-3 bullets)
         - How do these conversations relate to what was highlighted in the snippets?
         - Do the conversations provide additional context or depth to snippet items?

      Keep the summary focused and use bullet points. Target ~1500-2000 characters total.
      Be specific and technical - use actual feature names, technologies, and outcomes.
    PROMPT
  end
end
