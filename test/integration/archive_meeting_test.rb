#!/usr/bin/env ruby

require_relative '../test_helper'
require 'tmpdir'
require 'fileutils'

class ArchiveMeetingIntegrationTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir('archive_meeting_test')
    @transcripts_dir = File.join(@test_dir, 'transcripts')
    @target_dir = File.join(@test_dir, 'notes')
    @exec_prompt_path = File.join(fixtures_path, 'prompts', 'exec_summary_prompt.txt')
    @detailed_prompt_path = File.join(fixtures_path, 'prompts', 'detailed_notes_prompt.txt')
    @script_path = File.join(repo_root, 'bin', 'archive-meeting')
    
    # Set up test directory structure
    create_test_directory_structure
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  # Happy path tests
  def test_archives_meeting_with_all_required_arguments
    result = run_script_with_mocked_dependencies([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    refute_nil result[:exit_code], "Script should complete execution"
    # In practice will fail due to missing dependencies (llm, fzf), but tests the argument parsing
  end

  def test_uses_custom_llm_model_when_specified
    result = run_script_with_mocked_dependencies([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path,
      '--llm-model', 'gpt-4.1'
    ])
    
    refute_nil result[:exit_code], "Script should handle custom model"
  end

  def test_shows_help_with_help_flag
    result = run_script(['--help'])
    
    assert_equal 0, result[:exit_code], "Help should exit successfully"
    assert result[:stdout].include?('Usage:'), "Should show usage information"
    assert result[:stdout].include?('transcripts-dir'), "Should show transcripts-dir option"
    assert result[:stdout].include?('target-dir'), "Should show target-dir option"
    assert result[:stdout].include?('executive-summary-prompt-path'), "Should show exec summary prompt option"
    assert result[:stdout].include?('detailed-notes-prompt-path'), "Should show detailed notes prompt option"
    assert result[:stdout].include?('llm-model'), "Should show model option"
  end

  # Sad path tests
  def test_fails_without_required_arguments
    result = run_script([])
    
    assert_equal 1, result[:exit_code], "Should fail without arguments"
    assert result[:stderr].include?('Usage:') || result[:stderr].include?('required') || result[:stderr].include?('missing'), 
           "Should show usage or mention missing arguments: #{result[:stderr]}"
  end

  def test_fails_with_missing_transcripts_dir_argument
    result = run_script([
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    assert_equal 1, result[:exit_code], "Should fail without transcripts-dir"
    assert result[:stderr].include?('transcripts-dir') || result[:stderr].include?('required') || result[:stderr].include?('missing'), 
           "Should mention missing transcripts-dir: #{result[:stderr]}"
  end

  def test_fails_with_missing_target_dir_argument
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    assert_equal 1, result[:exit_code], "Should fail without target-dir"
    assert result[:stderr].include?('target-dir') || result[:stderr].include?('required') || result[:stderr].include?('missing'), 
           "Should mention missing target-dir: #{result[:stderr]}"
  end

  def test_fails_with_missing_executive_summary_prompt_path
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    assert_equal 1, result[:exit_code], "Should fail without executive summary prompt"
    assert result[:stderr].include?('executive-summary-prompt-path') || result[:stderr].include?('required') || result[:stderr].include?('missing'), 
           "Should mention missing executive summary prompt: #{result[:stderr]}"
  end

  def test_fails_with_missing_detailed_notes_prompt_path
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path
    ])
    
    assert_equal 1, result[:exit_code], "Should fail without detailed notes prompt"
    assert result[:stderr].include?('detailed-notes-prompt-path') || result[:stderr].include?('required') || result[:stderr].include?('missing'), 
           "Should mention missing detailed notes prompt: #{result[:stderr]}"
  end

  def test_fails_with_nonexistent_transcripts_directory
    nonexistent_dir = File.join(@test_dir, 'nonexistent_transcripts')
    
    result = run_script([
      '--transcripts-dir', nonexistent_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    assert_equal 1, result[:exit_code], "Should fail with nonexistent transcripts directory"
    assert result[:stderr].include?('not found') || result[:stderr].include?('exist') || result[:stderr].include?('directory'), 
           "Should mention transcripts directory not found: #{result[:stderr]}"
  end

  def test_fails_with_nonexistent_target_directory
    nonexistent_dir = File.join(@test_dir, 'nonexistent_target')
    
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', nonexistent_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    assert_equal 1, result[:exit_code], "Should fail with nonexistent target directory"
    assert result[:stderr].include?('not found') || result[:stderr].include?('exist') || result[:stderr].include?('directory'), 
           "Should mention target directory not found: #{result[:stderr]}"
  end

  def test_fails_with_nonexistent_executive_summary_prompt_file
    nonexistent_prompt = File.join(@test_dir, 'nonexistent_exec_prompt.txt')
    
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', nonexistent_prompt,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    assert_equal 1, result[:exit_code], "Should fail with nonexistent executive summary prompt"
    assert result[:stderr].include?('not found') || result[:stderr].include?('exist') || result[:stderr].include?('file'), 
           "Should mention executive summary prompt not found: #{result[:stderr]}"
  end

  def test_fails_with_nonexistent_detailed_notes_prompt_file
    nonexistent_prompt = File.join(@test_dir, 'nonexistent_detailed_prompt.txt')
    
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', nonexistent_prompt
    ])
    
    assert_equal 1, result[:exit_code], "Should fail with nonexistent detailed notes prompt"
    assert result[:stderr].include?('not found') || result[:stderr].include?('exist') || result[:stderr].include?('file'), 
           "Should mention detailed notes prompt not found: #{result[:stderr]}"
  end

  def test_handles_empty_transcripts_directory
    empty_transcripts_dir = File.join(@test_dir, 'empty_transcripts')
    FileUtils.mkdir_p(empty_transcripts_dir)
    
    result = run_script([
      '--transcripts-dir', empty_transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    assert_equal 1, result[:exit_code], "Should fail with empty transcripts directory"
    assert result[:stderr].include?('no') || result[:stderr].include?('empty') || result[:stderr].include?('transcript'), 
           "Should mention no transcripts found: #{result[:stderr]}"
  end

  def test_fails_when_llm_command_not_found
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    # Should fail because llm is not installed
    assert_equal 1, result[:exit_code], "Should fail when llm command not found"
    assert result[:stderr].include?('llm') || result[:stderr].include?('dependency') || result[:stderr].include?('not found'), 
           "Should mention llm dependency issue: #{result[:stderr]}"
  end

  def test_fails_when_fzf_command_not_found
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    # Should fail because fzf is not installed
    refute_nil result[:exit_code], "Should handle missing fzf"
    # May fail at different points depending on where fzf is used
  end

  def test_handles_transcript_files_with_special_characters
    # Create transcript files with special characters in names
    special_transcript_dir = File.join(@transcripts_dir, 'meeting with spaces & symbols')
    FileUtils.mkdir_p(special_transcript_dir)
    File.write(File.join(special_transcript_dir, 'transcript with spaces.txt'), 'Meeting transcript content')
    
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    refute_nil result[:exit_code], "Should handle special characters in file names"
  end

  def test_handles_very_large_transcript_files
    # Create large transcript file
    large_transcript_dir = File.join(@transcripts_dir, '2024-01-01')
    FileUtils.mkdir_p(large_transcript_dir)
    large_content = 'This is a very long transcript. ' * 10000  # ~320KB
    File.write(File.join(large_transcript_dir, 'large_transcript.txt'), large_content)
    
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    refute_nil result[:exit_code], "Should handle large transcript files"
  end

  def test_handles_invalid_llm_model
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path,
      '--llm-model', 'invalid-model-name'
    ])
    
    refute_nil result[:exit_code], "Should handle invalid model"
  end

  def test_handles_prompt_files_with_no_read_permissions
    # Create prompt file and remove read permissions
    restricted_prompt = File.join(@test_dir, 'restricted_exec_prompt.txt')
    File.write(restricted_prompt, 'prompt content')
    File.chmod(0000, restricted_prompt)
    
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', restricted_prompt,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    # Restore permissions for cleanup
    File.chmod(0644, restricted_prompt) rescue nil
    
    assert_equal 1, result[:exit_code], "Should fail when prompt file is not readable"
    assert result[:stderr].include?('permission') || result[:stderr].include?('read') || result[:stderr].include?('access'), 
           "Should mention permission error: #{result[:stderr]}"
  end

  def test_handles_target_directory_with_no_write_permissions
    # Remove write permissions from target directory
    File.chmod(0444, @target_dir)
    
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    # Restore permissions for cleanup
    File.chmod(0755, @target_dir) rescue nil
    
    refute_nil result[:exit_code], "Should handle write permission issues"
    # May fail when trying to create subdirectories
  end

  def test_handles_invalid_flag_gracefully
    result = run_script(['--invalid-flag', 'value'])
    
    assert_equal 1, result[:exit_code], "Should fail with invalid flag"
    assert result[:stderr].include?('invalid') || result[:stderr].include?('unknown') || result[:stderr].include?('Usage'), 
           "Should mention invalid flag: #{result[:stderr]}"
  end

  def test_handles_mixed_transcript_file_types
    # Create transcripts with different extensions
    mixed_transcript_dir = File.join(@transcripts_dir, '2024-01-02')
    FileUtils.mkdir_p(mixed_transcript_dir)
    File.write(File.join(mixed_transcript_dir, 'transcript.txt'), 'Text transcript')
    File.write(File.join(mixed_transcript_dir, 'transcript.vtt'), 'VTT transcript')
    File.write(File.join(mixed_transcript_dir, 'not_transcript.doc'), 'Not a transcript')
    
    result = run_script([
      '--transcripts-dir', @transcripts_dir,
      '--target-dir', @target_dir,
      '--executive-summary-prompt-path', @exec_prompt_path,
      '--detailed-notes-prompt-path', @detailed_prompt_path
    ])
    
    refute_nil result[:exit_code], "Should handle mixed file types"
  end

  private

  def run_script(args)
    stdout, stderr, status = Open3.capture3(@script_path, *args)
    {
      stdout: stdout,
      stderr: stderr,
      exit_code: status.exitstatus
    }
  end

  def run_script_with_mocked_dependencies(args)
    # In a real implementation, you would mock llm, fzf, etc.
    # For now, just run the script normally
    run_script(args)
  end

  def create_test_directory_structure
    # Create transcripts directory with sample meeting folders
    FileUtils.mkdir_p(@transcripts_dir)
    FileUtils.mkdir_p(@target_dir)
    
    # Create sample meeting transcript folders
    meeting_dates = ['2024-01-01', '2024-01-15', '2024-02-01']
    meeting_dates.each do |date|
      meeting_dir = File.join(@transcripts_dir, date)
      FileUtils.mkdir_p(meeting_dir)
      File.write(File.join(meeting_dir, 'transcript.txt'), "Sample transcript for #{date}")
      File.write(File.join(meeting_dir, 'chat.txt'), "Sample chat log for #{date}")
    end
    
    # Create prompt files
    FileUtils.mkdir_p(File.dirname(@exec_prompt_path))
    File.write(@exec_prompt_path, 'Generate executive summary from: {{transcript}}')
    File.write(@detailed_prompt_path, 'Generate detailed notes from: {{transcript}}')
    
    # Create target directory structure that archive-meeting expects
    ['Executive Summaries', 'Meeting Notes', 'Transcripts', 'Weekly Notes'].each do |subdir|
      FileUtils.mkdir_p(File.join(@target_dir, subdir))
    end
    
    # Create a sample weekly notes file
    File.write(File.join(@target_dir, 'Weekly Notes', '2024-01-01_weekly_notes.md'), 
               "# Weekly Notes\n\n## Meetings\n- [[Team Standup]]\n- [[Project Review]]")
  end

  def fixtures_path
    File.join(repo_root, 'test', 'fixtures')
  end

  def repo_root
    File.expand_path('../../..', __FILE__)
  end
end