# lib/github_deep_research_agent/retriever_node.rb
#
# Executes search operations based on PlannerNode's decisions

require "json"
require "set"
require "shellwords"
require_relative "../../lib/pocketflow"
require_relative "../../lib/utils"

module GitHubDeepResearchAgent
  class RetrieverNode < Pocketflow::Node
    def prep(shared)
      @shared = shared # Store shared context
      search_plan = shared[:next_search]

      if search_plan.nil?
        puts "No search plan found from PlannerNode"
        return nil
      end

      puts "=== RETRIEVAL PHASE ==="
      puts "Executing #{search_plan[:tool]} search with query: \"#{search_plan[:query]}\""

      search_plan
    end

    def exec(search_plan)
      return [] if search_plan.nil?

      tool = search_plan[:tool]
      collection = @shared[:collection]
      top_k = @shared[:top_k]
      script_dir = @shared[:script_dir]

      if tool == :hybrid
        # Run both semantic and keyword searches and combine results
        semantic_query = search_plan[:semantic_query]
        keyword_query = search_plan[:keyword_query]

        puts "Running semantic search with query: \"#{semantic_query}\""
        semantic_cmd = build_semantic_search_command(search_plan, script_dir, collection, top_k)

        semantic_output = Utils.run_cmd(semantic_cmd)
        semantic_results = JSON.parse(semantic_output)

        puts "Running keyword search with query: \"#{keyword_query}\""
        keyword_cmd = "#{script_dir}/search-github-conversations #{Shellwords.escape(keyword_query)}"

        keyword_output = Utils.run_cmd(keyword_cmd)
        keyword_results = JSON.parse(keyword_output)

        # Convert keyword search results to match semantic search format
        keyword_normalized = keyword_results.map do |result|
          {
            "payload" => {
              "url" => result["url"],
              "summary" => "" # No summary available from keyword search - will be enriched later
            },
            "score" => 0.0 # No relevance score from keyword search
          }
        end

        # Combine results and deduplicate by URL
        combined_results = semantic_results + keyword_normalized
        url_to_result = {}
        combined_results.each do |result|
          url = result.dig("payload", "url")
          next unless url
          # Keep the semantic result if we have both (it has score and summary)
          if !url_to_result[url] || result["score"] > 0
            url_to_result[url] = result
          end
        end

        search_results = url_to_result.values.first(top_k)
        puts "Combined #{semantic_results.length} semantic + #{keyword_results.length} keyword results into #{search_results.length} unique conversations"

        # Enrich keyword search results with summaries
        search_results.each do |result|
          url = result.dig("payload", "url")
          next unless url

          # Skip if already has a summary (from semantic search)
          next if result.dig("payload", "summary") && !result.dig("payload", "summary").empty?

          # Get or generate summary for this conversation
          summary = get_or_generate_summary(
            url,
            collection,
            script_dir,
            @shared[:cache_path]
          )

          # Update the result with the enriched summary
          result["payload"]["summary"] = summary
        end

      elsif tool == :keyword
        query = search_plan[:query]
        puts "Running keyword search with query..."
        search_cmd = "#{script_dir}/search-github-conversations #{Shellwords.escape(query)}"

        search_output = Utils.run_cmd(search_cmd)
        keyword_results = JSON.parse(search_output)

        # Convert keyword search results to match semantic search format
        search_results = keyword_results.map do |result|
          {
            "payload" => {
              "url" => result["url"],
              "summary" => "" # No summary available from keyword search - will be enriched later
            },
            "score" => 0.0 # No relevance score from keyword search
          }
        end

        # Limit results to top_k
        search_results = search_results.first(top_k)

        # Enrich keyword search results with summaries
        search_results.each do |result|
          url = result.dig("payload", "url")
          next unless url

          # Get or generate summary for this conversation
          summary = get_or_generate_summary(
            url,
            collection,
            script_dir,
            @shared[:cache_path]
          )

          # Update the result with the enriched summary
          result["payload"]["summary"] = summary
        end
      else
        query = search_plan[:query]
        puts "Running semantic search with query..."

        # Extract qualifiers from the query for semantic search
        semantic_query_info = build_semantic_query(query)

        # Build updated search plan with extracted qualifiers
        updated_search_plan = search_plan.merge(semantic_query_info)

        search_cmd = build_semantic_search_command(updated_search_plan, script_dir, collection, top_k)

        search_output = Utils.run_cmd(search_cmd)
        search_results = JSON.parse(search_output)
      end

      # Deduplicate URLs we already have
      existing_urls = @shared[:memory][:hits].map { |hit| hit[:url] }.to_set
      new_results = search_results.reject { |result| existing_urls.include?(result.dig("payload", "url")) }

      puts "Found #{new_results.length} new conversations after deduplication"

      if new_results.empty?
        puts "No new results found - all were duplicates"
        return []
      end

      # Fetch detailed data for new results
      new_enriched = []
      new_results.each_with_index do |result, i|
        url = result.dig("payload", "url")
        next unless url

        puts "Fetching details for new result #{i + 1}/#{new_results.length}: #{url}"

        begin
          fetch_cmd = "#{@shared[:script_dir]}/fetch-github-conversation"
          if @shared[:cache_path]
            fetch_cmd += " --cache-path #{Shellwords.escape(@shared[:cache_path])}"
          end
          fetch_cmd += " #{Shellwords.escape(url)}"

          conversation_json = Utils.Utils.run_cmd_safe(fetch_cmd)
          conversation_data = JSON.parse(conversation_json)

          metadata = extract_conversation_metadata(conversation_data)

          new_enriched << {
            url: url,
            summary: result.dig("payload", "summary") || "",
            score: result["score"],
            conversation: conversation_data
          }
        rescue => e
          puts "Failed to fetch #{url}: #{e.message}"
        end
      end

      puts "Successfully enriched #{new_enriched.length}/#{new_results.length} new conversations"

      # Enrich any conversations that still have empty summaries (from keyword searches)
      new_enriched.each do |enriched_result|
        url = enriched_result[:url]
        next unless url

        # Skip if already has a summary (from semantic search)
        next if enriched_result[:summary] && !enriched_result[:summary].empty?

        # Get or generate summary for this conversation
        summary = get_or_generate_summary(
          url,
          @shared[:collection],
          @shared[:script_dir],
          @shared[:cache_path]
        )

        # Update the result with the enriched summary
        enriched_result[:summary] = summary
      end

      new_enriched
    end

    def post(shared, prep_res, exec_res)
      return "final" if prep_res.nil? # No search plan

      # Store the query used for memory tracking
      query = prep_res[:semantic_query] || prep_res[:query] || "Unknown query"

      # Add new findings to memory
      shared[:memory][:hits].concat(exec_res)
      shared[:memory][:search_queries] << query

      # Add research notes
      if exec_res.any?
        notes = exec_res.map { |hit| "#{hit[:url]}: #{hit[:summary]}" }.join("\n")
        shared[:memory][:notes] << "Research iteration: #{notes}"
        puts "Added #{exec_res.length} new conversations to memory"
      else
        puts "No new conversations added this iteration"
      end

      # Increment depth
      shared[:current_depth] = (shared[:current_depth] || 0) + 1

      # Continue if under max depth, otherwise go to final report
      if shared[:current_depth] < shared[:max_depth] && exec_res.any?
        puts "Continuing to next research iteration..."
        "continue" # Go back to planning for next iteration
      else
        puts "Research complete, moving to final report..."

        # Clear unsupported claims if we were researching them (to avoid re-triggering claim verification loop)
        if shared[:unsupported_claims] && shared[:unsupported_claims].any?
          puts "Clearing unsupported claims after research attempt"
          shared[:unsupported_claims] = []
        end

        "final"
      end
    end

    EXECUTIVE_SUMMARY_PROMPT = <<~PROMPT
      # Executive summary instructions
      I need help summarizing a conversation from GitHub. Here are the rules I need you to follow:

      1. Concise, Informative Title: Begin with a clear, succinct title that encapsulates the main subject or decision at hand. The title should immediately set the context and importance of the issue or decision.
      2. Narrative-Driven Summary: Present the summary as a series of well-structured paragraphs. Avoid bullets, headers, or lists. Use a formal, professional tone, and ensure each paragraph builds logically on the previous one. Your goal is to convey a cohesive narrative of the conversation's evolution, from initial request to final decision or ongoing status.
      3. Complete Contextual Linking: Each time you mention or rely on a piece of information that came from a specific part of the conversation or a referenced resource, you must provide a direct link to it.
          - Comments by Contributors: When you cite or paraphrase something said by a participant, mention their @username plainly, then follow it immediately with a link in parentheses or integrated into the sentence.
            - For example: As @username suggested ([ref](URL)), the remediation plan requires additional time…
            - Note that @username itself is not linked. The link must be separate, placed after or within the sentence, not wrapping the username mention.
          - Events, Labels, or Status Changes: If you reference a point when the conversation moved stages or when a label was added/removed, follow the same linking pattern.
            - For example: Following the addition of the ROBOT: Ready for final review label (see [event record](URL)), the conversation shifted toward…
          - Referenced Documentation or Guides: If a guide, documentation page, or external resource is mentioned, embed the link in a phrase that clearly points to it.
            - For example: According to the shared key authentication guidelines (see [Flink documentation](URL)), this approach is discouraged…
            - All references that hinge upon a distinct resource, comment, or event available in the original conversation must be linked. No standalone links without contextual text; each link should be integrated into the narrative.
      4. Focus on Critical Content: Include only details that significantly influenced the direction, decisions, or outcomes. Omit administrative commentary, routine subscription messages, superficial technical details like code diffs, and exact merge timestamps, unless they directly influenced the final decision. Center on the key debates, decisions, constraints, and resolutions, and highlight the business or user impact rather than implementation minutiae.
      5. Alternatives, Status, and Next Steps: Where the conversation explored alternative solutions or future plans, clearly explain them and link to the comments or resources where these alternatives were discussed. If the resolution is partial or the decision involves further follow-up, summarize these implications and provide links to the final authoritative comments that set out those paths.
      6. Formal Tone, Dense Prose: Maintain a formal, authoritative tone. Write in complete, well-structured sentences. Integrate all references and links seamlessly, ensuring no extraneous formatting distracts from the narrative.
      7. Ignore Automated Bot Events: Do not include commentary, updates, or event records added by automated bots (e.g., @github-actions[bot]) unless they introduced a crucial piece of information or directly influenced the final outcome.

      By following these instructions, you will produce a tight executive summary that not only captures the essence of the conversation but also provides readers with direct, actionable links to every important piece of source material mentioned. This ensures that anyone reading the summary can delve deeper into the original conversation and resources as needed.
    PROMPT

    # Extracts conversation metadata from GitHub conversation data.
    def extract_conversation_metadata(conversation_data)
      # Determine type and extract conversation metadata
      conversation_type = if conversation_data["issue"]
        "issue"
      elsif conversation_data["pr"]
        "pull request"
      elsif conversation_data["discussion"]
        "discussion"
      else
        "unknown"
      end

      # Get the actual conversation object based on type
      conversation_obj = conversation_data["issue"] || conversation_data["pr"] || conversation_data["discussion"] || {}

      # Extract metadata for logging and return
      {
        type: conversation_type,
        title: conversation_obj["title"] || "Unknown title",
        state: conversation_obj["state"] || "unknown",
        comments_count: conversation_data["comments"]&.length || 0
      }
    end

    # Extracts qualifiers from user query and builds semantic search query.
    def build_semantic_query(user_query)
      # Extract repo: and author: qualifiers
      repo_match = user_query.match(/\brepo:(\S+)/)
      author_match = user_query.match(/\bauthor:(\S+)/)

      # Strip qualifiers from the query for semantic search
      semantic_query = user_query.dup
      semantic_query.gsub!(/\brepo:\S+/, '')
      semantic_query.gsub!(/\bauthor:\S+/, '')
      semantic_query.strip!

      # Clean up extra whitespace
      semantic_query.gsub!(/\s+/, ' ')

      {
        semantic_query: semantic_query,
        repo_filter: repo_match ? repo_match[1] : nil,
        author_filter: author_match ? author_match[1] : nil
      }
    end

    # Fetches existing summary from Qdrant using URL filter.
    def fetch_summary_from_qdrant(url, collection, script_dir)
      begin
        search_cmd = "#{script_dir}/semantic-search-github-conversations"
        search_cmd += " --collection #{Shellwords.escape(collection)}"
        search_cmd += " --filter url:#{Shellwords.escape(url)}"
        search_cmd += " --limit 1"
        search_cmd += " --format json"
        search_cmd += " #{Shellwords.escape('*')}"  # Dummy query since we're filtering by URL

        search_output = Utils.run_cmd(search_cmd)
        search_results = JSON.parse(search_output)

        if search_results.any?
          summary = search_results.first.dig("payload", "summary")
          return summary
        else
          return nil
        end
      rescue => e
        return nil
      end
    end

    # Generates a new summary for a GitHub conversation.
    def generate_new_summary(url, cache_path = nil)
      begin
        summarize_cmd = "#{File.dirname(__FILE__)}/../../bin/summarize-github-conversation"
        summarize_cmd += " --executive-summary-prompt #{Shellwords.escape(EXECUTIVE_SUMMARY_PROMPT)}"

        if cache_path
          summarize_cmd += " --cache-path #{Shellwords.escape(cache_path)}"
        end

        summarize_cmd += " #{Shellwords.escape(url)}"

        summary = Utils.run_cmd(summarize_cmd)

        return summary.strip
      rescue => e
        return ""
      end
    end

    # Gets or generates a summary for a GitHub conversation.
    def get_or_generate_summary(url, collection, script_dir, cache_path = nil)
      # Step 1: Try to fetch existing summary from Qdrant
      existing_summary = fetch_summary_from_qdrant(url, collection, script_dir)
      return existing_summary if existing_summary && !existing_summary.empty?

      # Step 2: Generate new summary
      return generate_new_summary(url, cache_path)
    end

    # Builds semantic search command with filters and ordering.
    def build_semantic_search_command(search_plan, script_dir, collection, top_k)
      cmd = "#{script_dir}/semantic-search-github-conversations"
      cmd += " #{Shellwords.escape(search_plan[:semantic_query] || search_plan[:query])}"
      cmd += " --collection #{Shellwords.escape(collection)}"
      cmd += " --limit #{top_k}"
      cmd += " --format json"

      # Add date filters if present
      if search_plan[:created_after]
        cmd += " --filter created_after:#{Shellwords.escape(search_plan[:created_after])}"
      end
      if search_plan[:created_before]
        cmd += " --filter created_before:#{Shellwords.escape(search_plan[:created_before])}"
      end

      # Add repo filter if present
      if search_plan[:repo_filter]
        cmd += " --filter repo:#{Shellwords.escape(search_plan[:repo_filter])}"
      end

      # Add author filter if present
      if search_plan[:author_filter]
        cmd += " --filter author:#{Shellwords.escape(search_plan[:author_filter])}"
      end

      # Add ordering if present
      if search_plan[:order_by]
        order_by_str = "#{search_plan[:order_by][:key]} #{search_plan[:order_by][:direction]}"
        cmd += " --order-by #{Shellwords.escape(order_by_str)}"
      end

      cmd
    end
  end
end
