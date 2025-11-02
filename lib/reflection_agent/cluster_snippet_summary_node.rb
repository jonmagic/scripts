module ReflectionAgent
  # ClusterSnippetSummaryNode - Summarizes snippets within each cluster
  #
  # This node processes each cluster in parallel using ParallelBatchNode.
  # For each cluster, an LLM reads all snippets and creates:
  # - Main themes (3-5 bullets)
  # - Key accomplishments (3-7 bullets)
  # - Important URLs mentioned (for conversation loading)
  # - Open questions/threads
  #
  # Output per cluster: ~1-2KB summary
  #
  # @example
  #   node = ClusterSnippetSummaryNode.new
  #   clusters = node.prep(shared)
  #   summaries = node.exec(cluster) # Called per cluster in parallel
  #   node.post(shared, clusters, summaries)
  class ClusterSnippetSummaryNode < Pocketflow::ParallelBatchNode
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Load clusters from previous stage
    #
    # @param shared [Hash] Workflow context
    # @return [Array<Hash>] Clusters to process
    def prep(shared)
      @shared = shared
      @skip_execution = false  # Initialize flag
      logger.info "=== STAGE 3: SUMMARIZE CLUSTER SNIPPETS (PARALLEL) ==="

      # Check if this stage already completed (for resume)
      output_path = File.join(shared[:reflection_dir], "03-cluster-snippet-summaries.json")
      if File.exist?(output_path)
        logger.info "Stage 3 already completed, loading existing summaries..."
        existing_summaries = JSON.parse(File.read(output_path))

        # Validate that summaries aren't corrupted (all nil values)
        if existing_summaries.all?(&:nil?)
          logger.warn "Existing summaries are corrupted (all nil), will regenerate..."
          File.delete(output_path)
          # Continue to normal processing (flag already false)
        else
          logger.info "✓ Loaded #{existing_summaries.length} existing cluster summaries"
          logger.info ""
          # Return empty array to skip execution
          @skip_execution = true
          @existing_summaries = existing_summaries
          return []
        end
      end

      clusters_path = File.join(shared[:reflection_dir], "02-clusters.json")
      clusters = JSON.parse(File.read(clusters_path))

      logger.info "Processing #{clusters.length} clusters in parallel..."
      logger.info ""

      clusters
    end

    # Summarize one cluster's snippets using LLM
    #
    # @param cluster [Hash] Single cluster to summarize
    # @return [Hash] Cluster summary
    def exec(cluster)
      cluster_id = cluster["id"]
      logger.info "[#{cluster_id}] Summarizing #{cluster['snippets'].length} snippets..."

      # Build combined snippets text
      snippets_text = cluster["snippets"].map do |snippet|
        "### #{snippet['title']}\n" \
        "**Period**: #{snippet['start_date']} to #{snippet['end_date']}\n\n" \
        "#{snippet['content']}\n\n" \
        "---\n"
      end.join("\n")

      # Build prompt
      prompt = Utils.fill_template(CLUSTER_SNIPPET_SUMMARY_PROMPT, {
        cluster_name: cluster["name"],
        cluster_period: "#{cluster['start_date']} to #{cluster['end_date']}",
        snippets_count: cluster["snippets"].length,
        snippets_text: snippets_text
      })

      # Call LLM
      summary_text = Utils.call_llm(prompt, @shared[:llm_model])

      # Extract URLs mentioned
      urls = extract_urls(summary_text)

      logger.info "[#{cluster_id}] ✓ Generated summary (#{urls.length} URLs extracted)"

      {
        cluster_id: cluster_id,
        cluster_name: cluster["name"],
        start_date: cluster["start_date"],
        end_date: cluster["end_date"],
        snippets_count: cluster["snippets"].length,
        summary: summary_text,
        urls_mentioned: urls
      }
    end

    # Write all cluster summaries to disk
    #
    # @param shared [Hash] Workflow context
    # @param prep_res [Array<Hash>] Clusters from prep
    # @param exec_res [Array<Hash>] Cluster summaries
    # @return [nil]
    def post(shared, prep_res, exec_res)
      # Use stored shared context (handles case where shared param might be nil)
      ctx = shared || @shared

      # If we skipped execution, use existing summaries
      summaries = @skip_execution ? @existing_summaries : exec_res

      # Write combined summaries (only if we didn't skip)
      unless @skip_execution
        summaries_path = File.join(ctx[:reflection_dir], "03-cluster-snippet-summaries.json")
        File.write(summaries_path, JSON.pretty_generate(summaries))
        logger.info ""
        logger.info "Wrote cluster summaries: #{summaries_path}"

        # Write individual cluster summary files
        summaries.each do |summary|
          cluster_file = File.join(
            ctx[:reflection_dir],
            "clusters",
            "#{summary[:cluster_id]}-snippet-summary.md"
          )
          File.write(cluster_file, summary[:summary])
        end
      end

      # Calculate total URLs (handle both symbol and string keys)
      total_urls = summaries.sum { |s| (s[:urls_mentioned] || s["urls_mentioned"] || []).length }

      # Write ledger
      ledger = {
        stage: "cluster_snippet_summary",
        status: @skip_execution ? "resumed" : "completed",
        summaries_count: summaries.length,
        total_urls_extracted: total_urls,
        next: "conversations_loader",
        createdAt: Time.now.utc.iso8601
      }
      ledger_path = File.join(ctx[:reflection_dir], "stage-3-cluster-snippet-summary.ledger.json")
      File.write(ledger_path, JSON.pretty_generate(ledger))

      logger.info ""
      if @skip_execution
        logger.info "✓ Stage 3 resumed: Loaded #{summaries.length} existing cluster summaries"
      else
        logger.info "✓ Stage 3 complete: Summarized #{summaries.length} clusters"
      end
      logger.info "  Total URLs extracted: #{total_urls}"
      logger.info "  Next: Load conversation summaries from vector DB"
      logger.info ""

      nil
    end

    private

    # Extract GitHub URLs from text
    #
    # @param text [String] Text to extract URLs from
    # @return [Array<String>] Unique GitHub URLs
    def extract_urls(text)
      urls = text.scan(%r{https://github\.com/[^\s\)]+})
      urls.map { |url| url.chomp('.').chomp(',') }.uniq
    end

    # Prompt for cluster snippet summarization
    CLUSTER_SNIPPET_SUMMARY_PROMPT = <<~PROMPT
      You are analyzing a cluster of weekly work snippets for a personal reflection.

      ## Cluster: {{cluster_name}}
      **Period**: {{cluster_period}}
      **Snippets**: {{snippets_count}}

      ## Snippets Content

      {{snippets_text}}

      ## Summarization Tasks

      Please create a concise summary with:

      1. **Main Themes** (3-5 bullets)
         - What were the dominant areas of focus in this period?
         - What patterns emerge across these weeks?

      2. **Key Accomplishments** (3-7 bullets)
         - What significant work was completed?
         - What decisions were made?
         - What milestones were reached?

      3. **GitHub URLs Referenced** (list)
         - Extract all GitHub URLs mentioned in the snippets
         - Include PRs, issues, discussions
         - Format as a markdown list

      4. **Open Threads** (2-4 bullets)
         - What was in progress?
         - What questions remained?
         - What needed follow-up?

      Keep the summary concise (≤500 words) but preserve important details and context.
      The URLs list is critical - it will be used to load detailed conversation summaries.
    PROMPT
  end
end
