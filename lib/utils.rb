# lib/utils.rb
#
# Shared utility methods for GitHub Deep Research Agent nodes

require "json"
require "logger"
require "open3"
require "tempfile"
require "shellwords"

module Utils
  # Public: Fills in template variables in a prompt string.
  #
  # template - The String template with {{variable}} placeholders.
  # variables - Hash of variable names to values.
  #
  # Returns the filled template as a String.
  def self.fill_template(template, variables)
    result = template.dup
    variables.each do |key, value|
      result.gsub!("{{#{key}}}", value.to_s)
    end
    result
  end

  # Public: Calls the LLM CLI for chat completion.
  #
  # prompt - The String prompt to send.
  # model - Optional String model name.
  #
  # Returns the LLM response as a String.
  def self.call_llm(prompt, model = nil)
    check_dependency("llm") # Check only when needed
    model_flag = model ? "-m #{Shellwords.escape(model)}" : ""

    # Use a temporary file to avoid "Argument list too long" errors
    Tempfile.create(["llm_prompt", ".txt"]) do |tmpfile|
      tmpfile.write(prompt)
      tmpfile.flush
      cmd = "llm #{model_flag} < #{Shellwords.escape(tmpfile.path)}"
      run_cmd_safe(cmd)
    end
  end

  # Public: Detects if an error message indicates context is too large for the model.
  #
  # error_message - The String error message to check.
  #
  # Returns true if the error indicates context is too large, false otherwise.
  def self.context_too_large_error?(error_message)
    # Azure OpenAI error patterns
    return true if error_message.include?("maximum context length")
    return true if error_message.include?("token limit")
    return true if error_message.include?("Request too large")
    return true if error_message.include?("context_length_exceeded")

    # OpenAI API error patterns
    return true if error_message.include?("This model's maximum context length")
    return true if error_message.include?("reduce the length of the messages")

    # Anthropic Claude error patterns
    return true if error_message.include?("max_tokens")
    return true if error_message.include?("context window")

    # Generic patterns
    return true if error_message.include?("too long")
    return true if error_message.include?("exceeds")

    false
  end

  # Public: Detects if an error message indicates a rate limit that should trigger compaction.
  #
  # error_message - The String error message to check.
  #
  # Returns true if the error indicates rate limiting, false otherwise.
  def self.rate_limit_error?(error_message)
    # Azure OpenAI rate limit patterns
    return true if error_message.include?("rate limit")
    return true if error_message.include?("Error code: 429")
    return true if error_message.include?("exceeded token rate limit")

    # OpenAI API rate limit patterns
    return true if error_message.include?("Rate limit reached")
    return true if error_message.include?("Too Many Requests")

    # Anthropic Claude rate limit patterns
    return true if error_message.include?("rate_limit_error")
    return true if error_message.include?("overloaded_error")

    false
  end

  # Public: Checks if a required command-line dependency is available in PATH.
  #
  # cmd - The String name of the command to check.
  #
  # Returns nothing. Exits if not found.
  def self.check_dependency(cmd)
    system("which #{cmd} > /dev/null 2>&1") || abort("Required dependency '#{cmd}' not found in PATH.")
  end

  # Public: Runs a shell command and returns stdout. Aborts if the command fails.
  #
  # cmd - The shell command to run (String).
  #
  # Returns the standard output of the command (String).
  # Aborts with an error message if the command fails.
  def self.run_cmd(cmd)
    stdout, stderr, status = Open3.capture3(cmd)
    abort "Command failed: #{cmd}\n#{stderr}" unless status.success?
    stdout.strip
  end

  # Public: Runs a shell command and returns stdout. Raises exception if the command fails.
  #
  # cmd - The shell command to run (String).
  #
  # Returns the standard output of the command (String).
  # Raises RuntimeError if the command fails.
  def self.run_cmd_safe(cmd)
    stdout, stderr, status = Open3.capture3(cmd)
    raise "Command failed: #{cmd}\n#{stderr}" unless status.success?
    stdout.strip
  end

  # Public: Gets the editor using Git's resolution order.
  #
  # Returns the editor command as a String.
  def self.get_git_editor
    # Follow Git's editor resolution order:
    # 1. GIT_EDITOR environment variable
    # 2. core.editor config value
    # 3. VISUAL environment variable
    # 4. EDITOR environment variable
    # 5. Fall back to system default

    return ENV["GIT_EDITOR"] if ENV["GIT_EDITOR"] && !ENV["GIT_EDITOR"].strip.empty?

    # Try git config core.editor
    git_config_editor = `git config --get core.editor 2>/dev/null`.strip
    return git_config_editor unless git_config_editor.empty?

    return ENV["VISUAL"] if ENV["VISUAL"] && !ENV["VISUAL"].strip.empty?
    return ENV["EDITOR"] if ENV["EDITOR"] && !ENV["EDITOR"].strip.empty?

    # Fall back to nano as a sensible default
    "nano"
  end

  # Public: Opens a text editor with the given content and returns the edited result.
  #
  # text - The String text to edit.
  # file_path - Optional String path to use instead of a temporary file.
  #
  # Returns the edited text as a String.
  def self.edit_text(text, file_path = nil)
    if file_path
      File.write(file_path, text)
      tmp_path = file_path
    else
      tmp = Tempfile.create(["research_edit", ".md"])
      tmp.puts text
      tmp.flush
      tmp_path = tmp.path
    end

    # Get editor using Git's resolution order
    editor = get_git_editor()

    # Open editor
    unless system("#{editor} #{tmp_path}")
      abort "Editor command failed: #{editor}"
    end

    # Read the edited content
    File.read(tmp_path)
  ensure
    tmp&.close unless file_path
  end

  # Public: Extracts conversation metadata from GitHub conversation data.
  #
  # conversation_data - The parsed JSON from fetch-github-conversation.
  #
  # Returns a Hash with conversation metadata and logging information.
  def self.extract_conversation_metadata(conversation_data)
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

  # Public: Extracts qualifiers from user query and builds semantic search query.
  #
  # user_query - String containing the user's query with potential qualifiers.
  #
  # Returns a Hash with:
  #   - :semantic_query - String with qualifiers stripped for embedding
  #   - :repo_filter - String with repo qualifier (e.g., "owner/name") or nil
  #   - :author_filter - String with author qualifier or nil
  def self.build_semantic_query(user_query)
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

  # Public: Builds semantic search command with filters and ordering.
  #
  # search_plan - Hash containing query and optional filters.
  # script_dir - String path to the script directory.
  # collection - String collection name.
  # top_k - Integer limit for results.
  #
  # Returns the command string.
  def self.build_semantic_search_command(search_plan, script_dir, collection, top_k)
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

  # Public: Parses structured semantic search response from LLM.
  #
  # llm_response - The String response from LLM (should be JSON).
  #
  # Returns a Hash with parsed query and filter information.
  def self.parse_semantic_search_response(llm_response)
    begin
      # Clean up response - remove markdown code blocks if present
      cleaned_response = llm_response.strip
      if cleaned_response.start_with?('```json')
        # Remove ```json from start and ``` from end
        cleaned_response = cleaned_response.gsub(/\A```json\s*/, '').gsub(/\s*```\z/, '')
      elsif cleaned_response.start_with?('```')
        # Remove generic ``` from start and end
        cleaned_response = cleaned_response.gsub(/\A```\s*/, '').gsub(/\s*```\z/, '')
      end

      # Try to parse as JSON first
      parsed = JSON.parse(cleaned_response.strip)

      # Validate required fields
      unless parsed["query"] && parsed["query"].is_a?(String)
        raise "Missing or invalid 'query' field"
      end

      result = { query: parsed["query"] }

      # Add optional fields if present
      if parsed["created_after"]
        result[:created_after] = parsed["created_after"]
      end

      if parsed["created_before"]
        result[:created_before] = parsed["created_before"]
      end

      if parsed["order_by"]
        # Parse order_by into field and direction
        parts = parsed["order_by"].split(" ", 2)
        if parts.length == 2 && parts[0] == "created_at" && %w[asc desc].include?(parts[1])
          result[:order_by] = { key: parts[0], direction: parts[1] }
        else
          # Add logging to warn about invalid order_by format
          result[:order_by] = nil
        end
      end

      result
    rescue JSON::ParserError
      # Fallback: treat as plain text query for backwards compatibility
      { query: llm_response.strip }
    rescue => e
      # Generic error handling
      { query: llm_response.strip }
    end
  end
end
