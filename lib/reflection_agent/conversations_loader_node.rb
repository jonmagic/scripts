module ReflectionAgent
  # ConversationsLoaderNode - Loads conversation summaries from vector DB
  #
  # This node:
  # 1. Extracts all unique URLs from cluster summaries
  # 2. Loads executive summaries from Qdrant vector DB
  # 3. Associates conversations back to their source clusters
  # 4. Deduplicates and prepares for per-cluster summarization
  #
  # @example
  #   node = ConversationsLoaderNode.new
  #   cluster_summaries = node.prep(shared)
  #   conversations = node.exec(cluster_summaries)
  #   node.post(shared, cluster_summaries, conversations)
  class ConversationsLoaderNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Load cluster summaries from previous stage
    #
    # @param shared [Hash] Workflow context
    # @return [Array<Hash>] Cluster summaries with URLs (or nil if skipping)
    def prep(shared)
      @shared = shared
      @skip_execution = false  # Initialize flag
      logger.info "=== STAGE 4: LOAD CONVERSATIONS ==="

      # Check if stage already completed
      output_path = File.join(shared[:reflection_dir], "04-conversations-by-cluster.json")
      if File.exist?(output_path)
        logger.info "Stage 4 already completed, loading existing conversations..."
        existing_data = JSON.parse(File.read(output_path))

        # Validate that data isn't corrupted (all nil values or empty)
        if existing_data.empty? || existing_data.all?(&:nil?)
          logger.warn "Existing conversations are corrupted, will regenerate..."
          File.delete(output_path)
          # Also delete the all-conversations file if it exists
          all_path = File.join(shared[:reflection_dir], "04-conversations-all.json")
          File.delete(all_path) if File.exist?(all_path)
          # Continue to normal processing (flag already false)
        else
          @skip_execution = true
          @existing_conversations = existing_data
          return nil  # Signal to skip execution
        end
      end

      summaries_path = File.join(shared[:reflection_dir], "03-cluster-snippet-summaries.json")
      JSON.parse(File.read(summaries_path))
    end

    # Load all conversations mentioned in snippets
    #
    # @param cluster_summaries [Array<Hash>] Cluster summaries with URLs (or nil if skipping)
    # @return [Hash] Loaded conversations organized by cluster (or nil if skipping)
    def exec(cluster_summaries)
      return nil if @skip_execution

      # Extract all unique URLs across all clusters
      all_urls = cluster_summaries.flat_map { |cs| cs["urls_mentioned"] }.uniq
      logger.info "Found #{all_urls.length} unique conversation URLs"

      # Load summaries from vector DB
      conversations = {}
      all_urls.each_with_index do |url, idx|
        if (idx + 1) % 10 == 0 || idx == all_urls.length - 1
          logger.info "  Loading conversation #{idx + 1}/#{all_urls.length}..."
        end

        summary = fetch_summary_from_vector_db(url)
        conversations[url] = {
          url: url,
          summary: summary,
          found: summary != url # If summary == url, it wasn't found
        }
      end

      # Count successes
      found_count = conversations.values.count { |c| c[:found] }
      logger.info ""
      logger.info "Successfully loaded #{found_count}/#{all_urls.length} conversation summaries"
      logger.info ""

      # Organize conversations by cluster
      cluster_conversations = cluster_summaries.map do |cs|
        cluster_urls = cs["urls_mentioned"]
        cluster_convs = cluster_urls.map { |url| conversations[url] }.compact

        {
          cluster_id: cs["cluster_id"],
          cluster_name: cs["cluster_name"],
          conversations: cluster_convs,
          found_count: cluster_convs.count { |c| c[:found] },
          total_count: cluster_urls.length
        }
      end

      {
        all_conversations: conversations,
        cluster_conversations: cluster_conversations
      }
    end

    # Write conversations data to disk
    #
    # @param shared [Hash] Workflow context
    # @param prep_res [Array<Hash>] Cluster summaries from prep (or nil if skipping)
    # @param exec_res [Hash] Loaded conversations (or nil if skipping)
    # @return [nil]
    def post(shared, prep_res, exec_res)
      # Use stored shared context (handles case where shared param might be nil)
      ctx = shared || @shared

      # If we skipped execution, use existing conversations
      if @skip_execution
        conversations_data = @existing_conversations

        # Calculate stats from existing data
        total_conversations = conversations_data.sum { |cc| (cc["total_count"] || cc[:total_count] || 0) }
        found_conversations = conversations_data.sum { |cc| (cc["found_count"] || cc[:found_count] || 0) }

        # Write ledger
        ledger = {
          stage: "conversations_loader",
          status: "resumed",
          total_conversations: total_conversations,
          found_in_vector_db: found_conversations,
          next: "cluster_conversation_summary",
          createdAt: Time.now.utc.iso8601
        }
        ledger_path = File.join(ctx[:reflection_dir], "stage-4-conversations-loader.ledger.json")
        File.write(ledger_path, JSON.pretty_generate(ledger))

        logger.info ""
        logger.info "✓ Stage 4 resumed: Loaded #{found_conversations} existing conversations"
        logger.info "  Next: Summarize conversations per cluster"
        logger.info ""
      else
        # Write all conversations
        all_path = File.join(ctx[:reflection_dir], "04-conversations-all.json")
        File.write(all_path, JSON.pretty_generate(exec_res[:all_conversations]))
        logger.info "Wrote all conversations: #{all_path}"

        # Write cluster-organized conversations
        cluster_path = File.join(ctx[:reflection_dir], "04-conversations-by-cluster.json")
        File.write(cluster_path, JSON.pretty_generate(exec_res[:cluster_conversations]))
        logger.info "Wrote cluster conversations: #{cluster_path}"

        # Write ledger
        total_found = exec_res[:all_conversations].values.count { |c| c[:found] }
        ledger = {
          stage: "conversations_loader",
          status: "completed",
          total_conversations: exec_res[:all_conversations].length,
          found_in_vector_db: total_found,
          next: "cluster_conversation_summary",
          createdAt: Time.now.utc.iso8601
        }
        ledger_path = File.join(ctx[:reflection_dir], "stage-4-conversations-loader.ledger.json")
        File.write(ledger_path, JSON.pretty_generate(ledger))

        logger.info ""
        logger.info "✓ Stage 4 complete: Loaded #{total_found} conversations"
        logger.info "  Next: Summarize conversations per cluster"
        logger.info ""
      end

      nil
    end

    private

    # Fetch executive summary from vector DB, or fetch and index if not found
    #
    # @param url [String] Conversation URL
    # @return [String] Executive summary or URL as fallback
    def fetch_summary_from_vector_db(url)
      # Use semantic search with URL filter to find this exact conversation
      search_cmd = "#{@shared[:script_dir]}/semantic-search-github-conversations"
      search_cmd += " #{Shellwords.escape(url)}"
      search_cmd += " --collection #{Shellwords.escape(@shared[:collection])}"
      search_cmd += " --filter #{Shellwords.escape("url:#{url}")}"
      search_cmd += " --limit 1"
      search_cmd += " --format json"

      begin
        output = Utils.run_cmd_safe(search_cmd)
        results = JSON.parse(output)

        if results.any? && results.first.dig("payload", "summary")
          logger.debug "  ✓ Found summary for #{url}"
          return results.first.dig("payload", "summary")
        else
          logger.warn "  ⚠ No summary found in vector DB for #{url}, fetching and indexing..."
          return fetch_and_index_conversation(url)
        end
      rescue => e
        logger.warn "  ⚠ Failed to fetch summary for #{url}: #{e.message}"
        logger.warn "  Attempting to fetch and index..."
        return fetch_and_index_conversation(url)
      end
    end

    # Fetch and index a conversation that's not in the vector DB
    #
    # @param url [String] Conversation URL
    # @return [String] Executive summary or URL as fallback
    def fetch_and_index_conversation(url)
      # Create JSON array with single conversation
      conversation_json = JSON.generate([{ url: url }])

      # Step 1: Fetch the conversation to cache
      fetch_cmd = "#{@shared[:script_dir]}/fetch-github-conversations"
      fetch_cmd += " --cache-path #{Shellwords.escape(@shared[:cache_path])}"

      begin
        IO.popen(fetch_cmd, "r+") do |io|
          io.write(conversation_json)
          io.close_write
          io.read # Consume output
        end

        unless $?.success?
          logger.warn "    ✗ Failed to fetch conversation"
          return url
        end
      rescue => e
        logger.warn "    ✗ Failed to fetch: #{e.message}"
        return url
      end

      # Step 2: Index the conversation
      index_cmd = "#{@shared[:script_dir]}/index-summaries"
      index_cmd += " --executive-summary-prompt-path #{Shellwords.escape(@shared[:executive_summary_prompt_path])}"
      index_cmd += " --topics-prompt-path #{Shellwords.escape(@shared[:topics_prompt_path])}"
      index_cmd += " --collection #{Shellwords.escape(@shared[:collection])}"
      index_cmd += " --cache-path #{Shellwords.escape(@shared[:cache_path])}"

      begin
        IO.popen(index_cmd, "r+") do |io|
          io.write(conversation_json)
          io.close_write
          io.read # Consume output
        end

        unless $?.success?
          logger.warn "    ✗ Failed to index conversation"
          return url
        end

        logger.info "    ✓ Successfully fetched and indexed"
      rescue => e
        logger.warn "    ✗ Failed to index: #{e.message}"
        return url
      end

      # Step 3: Try to retrieve the summary again
      search_cmd = "#{@shared[:script_dir]}/semantic-search-github-conversations"
      search_cmd += " #{Shellwords.escape(url)}"
      search_cmd += " --collection #{Shellwords.escape(@shared[:collection])}"
      search_cmd += " --filter #{Shellwords.escape("url:#{url}")}"
      search_cmd += " --limit 1"
      search_cmd += " --format json"

      begin
        output = Utils.run_cmd_safe(search_cmd)
        results = JSON.parse(output)

        if results.any? && results.first.dig("payload", "summary")
          return results.first.dig("payload", "summary")
        end
      rescue => e
        logger.warn "    ✗ Failed to retrieve after indexing: #{e.message}"
      end

      # Fallback: return URL
      url
    end
  end
end
