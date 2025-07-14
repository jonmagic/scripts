module GitHubDeepResearchAgent
  # ContextCompactionNode - Reduces conversation context to fit LLM model limits
  #
  # See lib/github_deep_research_agent.rb for architecture and workflow details.
  #
  # ## Overview
  # When accumulated conversation data exceeds LLM context limits, this node applies
  # progressive compaction strategies to preserve the most valuable content while fitting
  # within technical constraints. Compaction is triggered automatically and is safe to retry.
  #
  # ## Pipeline Position
  # - Input: Large conversation dataset from shared memory
  # - Output: Compacted dataset for downstream nodes
  #
  # @example
  #   node = ContextCompactionNode.new
  #   result = node.prep(shared)
  #   info = node.exec(result)
  #   status = node.post(shared, result, info)
  class ContextCompactionNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Analyze context size and apply compaction strategy if needed.
    #
    # @param shared [Hash] Workflow context with :memory, :compaction_attempts
    # @return [Hash, String, nil] Compaction info, "proceed_anyway", or nil
    def prep(shared)
      @shared = shared # Store shared context for downstream methods
      logger.info "=== CONTEXT COMPACTION PHASE ==="

      # Track compaction attempts to prevent infinite loops
      compaction_attempts = shared[:compaction_attempts] || 0
      max_compaction_attempts = 3

      # Safety check: Stop if we've reached maximum compaction attempts
      if compaction_attempts >= max_compaction_attempts
        logger.info "Maximum compaction attempts (#{max_compaction_attempts}) reached. Cannot reduce context further."
        return nil
      end

      # Extract conversation data from shared memory
      hits = shared[:memory][:hits]

      # Safety check: Don't compact if we already have minimal conversations
      if hits.length <= 3
        logger.info "Cannot compact further—only #{hits.length} conversations remain."
        logger.info "Proceeding with minimal context and hoping for the best..."
        return "proceed_anyway"
      end

      logger.info "Attempt #{compaction_attempts + 1}/#{max_compaction_attempts}: Compacting research context to fit model limits"
      logger.info "Starting with #{hits.length} conversations"

      # Sort conversations by priority using composite scoring strategy
      # This ensures we remove the least valuable conversations first
      sort_conversations_by_priority!(hits)

      # Determine compaction strategy based on attempt number
      # Each attempt becomes progressively more aggressive
      if compaction_attempts == 0
        # First attempt: Conservative removal of lowest-priority conversations
        removal_count = (hits.length * 0.3).ceil
        strategy = "Remove bottom 30% by priority"
      elsif compaction_attempts == 1
        # Second attempt: More aggressive removal plus detail stripping
        removal_count = (hits.length * 0.5).ceil
        strategy = "Remove bottom 50% by priority and strip conversation details"
      else
        # Final attempt: Keep only the most essential conversations
        removal_count = hits.length - (hits.length * 0.25).ceil
        strategy = "Keep only top 25% with minimal data"
      end

      logger.info "Strategy: #{strategy}"
      logger.info "Will remove #{removal_count} conversations, keeping #{hits.length - removal_count}"

      # Remove lower-priority conversations from the end of sorted array
      removed_conversations = hits.pop(removal_count)

      # For second and third attempts, also strip conversation details to save space
      if compaction_attempts >= 1
        logger.info "Stripping conversation details to reduce context size..."

        hits.each do |hit|
          if hit[:conversation]
            # Keep only essential conversation metadata, remove full content
            conversation = hit[:conversation]
            essential_data = {}

            # Preserve main conversation object with minimal fields
            # Each conversation type (issue/PR/discussion) has different essential fields
            if conversation["issue"]
              essential_data["issue"] = {
                "title" => conversation["issue"]["title"],
                "state" => conversation["issue"]["state"],
                "url" => conversation["issue"]["url"],
                "created_at" => conversation["issue"]["created_at"],
                "updated_at" => conversation["issue"]["updated_at"]
              }
            elsif conversation["pr"]
              essential_data["pr"] = {
                "title" => conversation["pr"]["title"],
                "state" => conversation["pr"]["state"],
                "url" => conversation["pr"]["url"],
                "created_at" => conversation["pr"]["created_at"],
                "updated_at" => conversation["pr"]["updated_at"],
                "merged" => conversation["pr"]["merged"]  # Critical for PR context
              }
            elsif conversation["discussion"]
              essential_data["discussion"] = {
                "title" => conversation["discussion"]["title"],
                "url" => conversation["discussion"]["url"],
                "created_at" => conversation["discussion"]["created_at"],
                "updated_at" => conversation["discussion"]["updated_at"]
              }
            end

            # Keep structural information as counts rather than full content
            # This preserves activity indicators while saving massive space
            essential_data["comments_count"] = conversation["comments"]&.length || 0
            essential_data["reviews_count"] = conversation["reviews"]&.length || 0
            essential_data["review_comments_count"] = conversation["review_comments"]&.length || 0

            # Replace full conversation with essential data
            hit[:conversation] = essential_data
          end
        end
      end

      # Update shared memory with compacted data for downstream processing
      shared[:memory][:hits] = hits

      # Return compaction metadata for tracking and logging
      {
        strategy: strategy,
        removed_count: removal_count,
        remaining_count: hits.length,
        compaction_attempt: compaction_attempts + 1
      }
    end

    # Log compaction results and validate strategy application.
    #
    # @param compaction_info [Hash, String, nil] Result from prep()
    # @return [Hash, String, nil] Passes through input for post()
    def exec(compaction_info)
      # Handle edge case where preparation failed or reached limits
      return nil if compaction_info.nil?

      # Handle case where compaction was bypassed due to minimal context
      return "proceed_anyway" if compaction_info == "proceed_anyway"

      # Log successful compaction results for user feedback and debugging
      logger.info "Applied compaction strategy: #{compaction_info[:strategy]}"
      logger.info "Removed #{compaction_info[:removed_count]} conversations"
      logger.info "#{compaction_info[:remaining_count]} conversations remaining"

      # Return compaction info unchanged for post-processing
      compaction_info
    end

    # Update workflow state and coordinate retry logic after compaction.
    #
    # @param shared [Hash] Workflow context to update
    # @param prep_res [Hash, String, nil] Result from prep()
    # @param exec_res [Hash, String, nil] Result from exec()
    # @return [String] Workflow routing signal ("retry" or "proceed_anyway")
    def post(shared, prep_res, exec_res)
      # Handle edge cases where compaction was skipped or failed
      return "proceed_anyway" if prep_res.nil? || exec_res == "proceed_anyway"

      # Update attempt counter in shared context for future compaction decisions
      compaction_attempts = (shared[:compaction_attempts] || 0) + 1
      shared[:compaction_attempts] = compaction_attempts

      logger.info "\u2713 Context compaction attempt #{compaction_attempts} completed"

      # Implement rate limiting delay to prevent immediate retry failures
      # This is crucial because:
      # 1. Model providers often have per-minute rate limits
      # 2. Large context processing may have triggered temporary throttling
      # 3. Memory cleanup after compaction takes time
      # 4. Immediate retries often hit the same limits that triggered compaction
      sleep_duration = 60
      logger.info "Waiting #{sleep_duration} seconds after compaction before retrying..."
      sleep(sleep_duration)

      # Signal workflow to retry the operation that triggered compaction
      # Typically this means retrying final report generation with compacted context
      "retry"
    end

    # Sort conversations by priority for compaction (in place).
    #
    # @param hits [Array<Hash>] Array of conversation hashes
    # @return [Array<Hash>] Sorted array (modifies in place)
    def sort_conversations_by_priority!(hits)
      hits.sort_by! do |hit|
        composite_score = 0

        # Strategy 1: Prioritize hits with substantive summaries (+10 points)
        # This is the strongest signal of conversation value since summaries
        # indicate the conversation was processed and found to contain meaningful content
        unless hit[:summary].to_s.strip.empty?
          composite_score += 10
        end

        # Strategy 2: Use relevance score when available
        # Vector similarity scores from semantic search provide objective
        # measures of how well conversations match research objectives
        score = hit[:score] || 0
        if score > 0
          composite_score += score
        end

        # Strategy 3: Slight bonus for earlier discoveries (more context)
        # Earlier-found conversations often have broader context and were
        # identified in primary searches rather than follow-up queries
        # Assume lower array index = found earlier in research process
        iteration_bonus = hits.length - hits.index(hit)
        composite_score += (iteration_bonus * 0.1)

        # Sort in descending order (highest priority first)
        # Negative value ensures highest scores appear at array start
        -composite_score
      end

      # Return the sorted array (though sorting happens in place)
      hits
    end
  end
end
