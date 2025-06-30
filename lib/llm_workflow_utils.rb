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

  # Selects meeting notes section using LLM and fzf
  #
  # latest_weekly_notes - String path to the latest weekly notes file
  # summary_file - String path to the executive summary file
  # llm_model - String model name or nil
  #
  # Returns String containing the selected meeting notes entry
  def self.select_meeting_notes_section(latest_weekly_notes:, summary_file:, llm_model:)
    weekly_content = File.read(latest_weekly_notes)
    summary_content = File.read(summary_file)

    # Use LLM to suggest meeting notes sections
    llm_prompt = "Based on this executive summary, suggest which meeting notes section this should go in (return just the filename/section name):\n\n#{summary_content}\n\nWeekly notes context:\n#{weekly_content}"

    model_flag = LlmUtils.new.llm_model_flag(llm_model)
    cmd = "llm #{model_flag}".strip

    suggested_section, _ = Open3.capture2(cmd, stdin_data: llm_prompt)

    # Use fzf to let user select/confirm the section
    fzf_input = suggested_section.strip
    selected, _ = Open3.capture2("fzf --prompt='Select meeting notes section: '", stdin_data: fzf_input)

    selected.strip
  end
end
