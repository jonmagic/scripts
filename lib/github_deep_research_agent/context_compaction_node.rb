# lib/github_deep_research_agent/context_compaction_node.rb
#
# Handles context compaction when conversation data exceeds model limits

require_relative "../../lib/pocketflow"

module GitHubDeepResearchAgent
  class ContextCompactionNode < Pocketflow::Node
    def prep(shared)
      @shared = shared
      puts "=== CONTEXT COMPACTION PHASE ==="

      compaction_attempts = shared[:compaction_attempts] || 0
      max_compaction_attempts = 3

      if compaction_attempts >= max_compaction_attempts
        puts "Maximum compaction attempts (#{max_compaction_attempts}) reached. Cannot reduce context further."
        return nil
      end

      hits = shared[:memory][:hits]

      if hits.length <= 3
        puts "Cannot compact further—only #{hits.length} conversations remain."
        puts "Proceeding with minimal context and hoping for the best..."
        return "proceed_anyway"
      end

      puts "Attempt #{compaction_attempts + 1}/#{max_compaction_attempts}: Compacting research context to fit model limits"
      puts "Starting with #{hits.length} conversations"

      # Sort conversations by priority using composite scoring strategy
      sort_conversations_by_priority!(hits)

      # Determine compaction strategy based on attempt number
      if compaction_attempts == 0
        # First attempt: Remove bottom 30% of conversations
        removal_count = (hits.length * 0.3).ceil
        strategy = "Remove bottom 30% by priority"
      elsif compaction_attempts == 1
        # Second attempt: Remove bottom 50% of conversations and strip conversation details
        removal_count = (hits.length * 0.5).ceil
        strategy = "Remove bottom 50% by priority and strip conversation details"
      else
        # Final attempt: Keep only top 25% and minimal data
        removal_count = hits.length - (hits.length * 0.25).ceil
        strategy = "Keep only top 25% with minimal data"
      end

      puts "Strategy: #{strategy}"
      puts "Will remove #{removal_count} conversations, keeping #{hits.length - removal_count}"

      # Remove lower-priority conversations
      removed_conversations = hits.pop(removal_count)

      # For second and third attempts, also strip conversation details
      if compaction_attempts >= 1
        puts "Stripping conversation details to reduce context size..."

        hits.each do |hit|
          if hit[:conversation]
            # Keep only essential conversation metadata, remove full content
            conversation = hit[:conversation]
            essential_data = {}

            # Preserve main conversation object with minimal fields
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
                "merged" => conversation["pr"]["merged"]
              }
            elsif conversation["discussion"]
              essential_data["discussion"] = {
                "title" => conversation["discussion"]["title"],
                "url" => conversation["discussion"]["url"],
                "created_at" => conversation["discussion"]["created_at"],
                "updated_at" => conversation["discussion"]["updated_at"]
              }
            end

            # Keep comment count but not full comment content
            essential_data["comments_count"] = conversation["comments"]&.length || 0
            essential_data["reviews_count"] = conversation["reviews"]&.length || 0
            essential_data["review_comments_count"] = conversation["review_comments"]&.length || 0

            hit[:conversation] = essential_data
          end
        end
      end

      # Update shared memory with compacted data
      shared[:memory][:hits] = hits

      {
        strategy: strategy,
        removed_count: removal_count,
        remaining_count: hits.length,
        compaction_attempt: compaction_attempts + 1
      }
    end

    def exec(compaction_info)
      return nil if compaction_info.nil?
      return "proceed_anyway" if compaction_info == "proceed_anyway"

      puts "Applied compaction strategy: #{compaction_info[:strategy]}"
      puts "Removed #{compaction_info[:removed_count]} conversations"
      puts "#{compaction_info[:remaining_count]} conversations remaining"

      compaction_info
    end

    def post(shared, prep_res, exec_res)
      return "proceed_anyway" if prep_res.nil? || exec_res == "proceed_anyway"

      compaction_attempts = (shared[:compaction_attempts] || 0) + 1
      shared[:compaction_attempts] = compaction_attempts

      puts "✓ Context compaction attempt #{compaction_attempts} completed"

      # Sleep briefly after compaction to avoid immediately hitting rate limits again
      sleep_duration = 60
      puts "Waiting #{sleep_duration} seconds after compaction before retrying..."
      sleep(sleep_duration)

      "retry" # Signal to retry the final report
    end

    # Sorts conversations by priority for context compaction.
    #
    # This implements a composite scoring strategy that prioritizes:
    # 1. Conversations with non-empty summaries (+10 points)
    # 2. Higher relevance scores (when available)
    # 3. Conversations found in earlier iterations (recency bonus)
    #
    # hits - Array of conversation hashes with :summary, :score, :url keys
    #
    # Returns the sorted array (modifies in place).
    def sort_conversations_by_priority!(hits)
      hits.sort_by! do |hit|
        composite_score = 0

        # Strategy 1: Prioritize hits with summaries (+10 points)
        unless hit[:summary].to_s.strip.empty?
          composite_score += 10
        end

        # Strategy 2: Use relevance score when available
        score = hit[:score] || 0
        if score > 0
          composite_score += score
        end

        # Strategy 3: Slight bonus for earlier discoveries (more context)
        # Assume lower array index = found earlier
        iteration_bonus = hits.length - hits.index(hit)
        composite_score += (iteration_bonus * 0.1)

        # Sort in descending order (highest priority first)
        -composite_score
      end

      hits
    end
  end
end
