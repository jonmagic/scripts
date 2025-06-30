require_relative 'llm_utils'
require_relative 'shell_utils'
require 'tempfile'
require 'fileutils'

# LlmWorkflowUtils: Higher-level LLM workflow utilities
#
# Provides complex LLM workflow operations that combine multiple steps
module LlmWorkflowUtils
  include LlmUtils
  include ShellUtils

  # Processes input file with LLM using a prompt and saves result to output file
  #
  # input_file - String path to the source input file
  # output_file - String path to the output file
  # llm_model - String model name or nil
  # prompt_path - String path to the LLM prompt template
  #
  # Returns nothing. Creates the output file.
  def self.process_and_save_with_llm(input_file:, output_file:, llm_model:, prompt_path:)
    input_content = File.read(input_file)
    model_flag = LlmUtils.new.llm_model_flag(llm_model)
    cmd = "llm -f #{Shellwords.escape(prompt_path)} #{model_flag}".strip

    output, _ = Open3.capture2(cmd, stdin_data: input_content)
    File.write(output_file, output)
  end

  # Processes input file with LLM using a prompt and returns result
  #
  # input_file - String path to the source input file
  # llm_model - String model name or nil
  # prompt_path - String path to the LLM prompt template
  #
  # Returns String containing the generated output
  def self.process_with_llm(input_file:, llm_model:, prompt_path:)
    input_content = File.read(input_file)
    model_flag = LlmUtils.new.llm_model_flag(llm_model)
    cmd = "llm -f #{Shellwords.escape(prompt_path)} #{model_flag}".strip

    output, _ = Open3.capture2(cmd, stdin_data: input_content)
    output.strip
  end
end
