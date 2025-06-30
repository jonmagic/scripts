require 'open3'
require 'shellwords'

# LlmUtils module provides LLM command-line utilities
module LlmUtils
  # Returns the model flag for the llm command, or an empty string if no model is specified.
  #
  # llm_model - The String model name or nil.
  #
  # Returns a String suitable for the llm command.
  def llm_model_flag(llm_model)
    llm_model && !llm_model.strip.empty? ? "-m #{Shellwords.escape(llm_model)}" : ""
  end

  # Execute llm command with given prompt and input
  #
  # prompt_path - String path to prompt file
  # input - String input to send to LLM
  # llm_model - String model name or nil
  #
  # Returns the LLM output as a String
  def execute_llm(prompt_path, input, llm_model = nil)
    model_flag = llm_model_flag(llm_model)
    cmd = "llm -f #{Shellwords.escape(prompt_path)} #{model_flag}".strip
    
    stdout, stderr, status = Open3.capture3(cmd, stdin_data: input)
    unless status.success?
      raise "LLM command failed: #{stderr}"
    end
    
    stdout
  end
end