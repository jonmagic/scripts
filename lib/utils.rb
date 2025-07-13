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
end
