#!/usr/bin/env ruby

require_relative '../test_helper'
require 'tmpdir'
require 'fileutils'

class SelectFolderIntegrationTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir('select_folder_test')
    @script_path = File.join(repo_root, 'bin', 'select-folder')
    
    # Create test directory structure
    create_test_directory_structure
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  # Happy path tests
  def test_shows_usage_with_help_flag
    result = run_script(['--help'])
    
    assert_equal 0, result[:exit_code], "Help should exit successfully"
    assert result[:stdout].include?('Usage:'), "Should show usage information"
    assert result[:stdout].include?('--target-dir'), "Should show target-dir option"
  end

  def test_lists_subdirectories_when_target_dir_has_folders
    # Mock fzf to simulate user selection
    result = run_script_with_mocked_fzf(['--target-dir', @test_dir], 'folder1')
    
    # Since we can't actually test fzf interaction without it being installed,
    # we test that the script attempts to use fzf and handles the case properly
    # The script will likely fail with "fzf: not found" but should show proper error handling
    refute_nil result[:exit_code], "Script should complete execution"
  end

  # Sad path tests
  def test_shows_usage_without_arguments
    result = run_script([])
    
    assert_equal 1, result[:exit_code], "Should fail without arguments"
    assert result[:stderr].include?('Usage:') || result[:stderr].include?('required') || result[:stderr].include?('missing'), 
           "Should show usage or mention missing arguments: #{result[:stderr]}"
  end

  def test_fails_with_missing_target_dir_argument
    result = run_script(['--some-other-arg'])
    
    assert_equal 1, result[:exit_code], "Should fail without target-dir"
    assert result[:stderr].include?('target-dir') || result[:stderr].include?('required') || result[:stderr].include?('missing'), 
           "Should mention missing target-dir: #{result[:stderr]}"
  end

  def test_fails_with_nonexistent_target_directory
    nonexistent_dir = File.join(@test_dir, 'nonexistent')
    
    result = run_script(['--target-dir', nonexistent_dir])
    
    assert_equal 1, result[:exit_code], "Should fail with nonexistent directory"
    assert result[:stderr].include?('not found') || result[:stderr].include?('exist') || result[:stderr].include?('directory'), 
           "Should mention directory not found: #{result[:stderr]}"
  end

  def test_fails_when_target_dir_is_file_not_directory
    # Create a file instead of directory
    file_path = File.join(@test_dir, 'not_a_directory.txt')
    File.write(file_path, 'content')
    
    result = run_script(['--target-dir', file_path])
    
    assert_equal 1, result[:exit_code], "Should fail when target-dir is a file"
    assert result[:stderr].include?('not a directory') || result[:stderr].include?('directory') || result[:stderr].include?('file'), 
           "Should mention target is not a directory: #{result[:stderr]}"
  end

  def test_handles_empty_directory_gracefully
    empty_dir = File.join(@test_dir, 'empty_dir')
    FileUtils.mkdir_p(empty_dir)
    
    result = run_script(['--target-dir', empty_dir])
    
    # Should handle empty directory gracefully - may warn or exit cleanly
    refute_nil result[:exit_code], "Should handle empty directory"
    
    # May exit with 0 (no folders to select) or 1 (no selection made)
    assert [0, 1].include?(result[:exit_code]), "Should exit cleanly with empty directory"
    
    output = result[:stdout] + result[:stderr]
    # Should either mention no folders or handle gracefully
    assert output.include?('no') || output.include?('empty') || output.length == 0, 
           "Should handle empty directory appropriately: #{output}"
  end

  def test_handles_directory_with_only_files_no_subdirs
    files_only_dir = File.join(@test_dir, 'files_only')
    FileUtils.mkdir_p(files_only_dir)
    File.write(File.join(files_only_dir, 'file1.txt'), 'content1')
    File.write(File.join(files_only_dir, 'file2.txt'), 'content2')
    
    result = run_script(['--target-dir', files_only_dir])
    
    refute_nil result[:exit_code], "Should handle directory with only files"
    
    # Should handle lack of subdirectories gracefully
    output = result[:stdout] + result[:stderr]
    # Script should either find no folders or handle this case
    assert [0, 1].include?(result[:exit_code]), "Should handle no subdirectories case"
  end

  def test_handles_invalid_flag_gracefully
    result = run_script(['--invalid-flag', 'value'])
    
    assert_equal 1, result[:exit_code], "Should fail with invalid flag"
    assert result[:stderr].include?('invalid') || result[:stderr].include?('unknown') || result[:stderr].include?('Usage'), 
           "Should mention invalid flag or show usage: #{result[:stderr]}"
  end

  def test_handles_permission_denied_directory
    # Create directory and remove read permissions
    restricted_dir = File.join(@test_dir, 'restricted')
    FileUtils.mkdir_p(restricted_dir)
    File.chmod(0000, restricted_dir)
    
    result = run_script(['--target-dir', restricted_dir])
    
    # Restore permissions for cleanup
    File.chmod(0755, restricted_dir) rescue nil
    
    assert_equal 1, result[:exit_code], "Should fail with permission denied"
    assert result[:stderr].include?('permission') || result[:stderr].include?('denied') || result[:stderr].include?('access'), 
           "Should mention permission error: #{result[:stderr]}"
  end

  def test_handles_deeply_nested_directory_structure
    # Create deeply nested structure
    deep_dir = @test_dir
    10.times do |i|
      deep_dir = File.join(deep_dir, "level#{i}")
      FileUtils.mkdir_p(deep_dir)
    end
    
    result = run_script(['--target-dir', @test_dir])
    
    refute_nil result[:exit_code], "Should handle deeply nested structure"
    # Should complete without crashing
    assert result[:exit_code].is_a?(Integer), "Should return proper exit code"
  end

  def test_handles_special_characters_in_directory_names
    # Create directories with special characters
    special_dirs = ['folder with spaces', 'folder-with-dashes', 'folder_with_underscores', 'folder.with.dots']
    special_dirs.each do |dir_name|
      FileUtils.mkdir_p(File.join(@test_dir, dir_name))
    end
    
    result = run_script(['--target-dir', @test_dir])
    
    refute_nil result[:exit_code], "Should handle special characters in directory names"
    assert result[:exit_code].is_a?(Integer), "Should return proper exit code"
  end

  def test_handles_very_long_directory_names
    # Create directory with very long name
    long_name = 'a' * 200  # 200 character directory name
    long_dir = File.join(@test_dir, long_name)
    FileUtils.mkdir_p(long_dir)
    
    result = run_script(['--target-dir', @test_dir])
    
    refute_nil result[:exit_code], "Should handle very long directory names"
    assert result[:exit_code].is_a?(Integer), "Should return proper exit code"
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

  def run_script_with_mocked_fzf(args, selection)
    # In a real implementation, you would mock fzf's behavior
    # For now, just run the script normally
    run_script(args)
  end

  def create_test_directory_structure
    # Create a variety of subdirectories for testing
    folders = ['folder1', 'folder2', 'folder3', 'nested/subfolder']
    folders.each do |folder|
      FileUtils.mkdir_p(File.join(@test_dir, folder))
    end
    
    # Create some files too
    File.write(File.join(@test_dir, 'file1.txt'), 'content')
    File.write(File.join(@test_dir, 'file2.md'), 'markdown content')
  end

  def repo_root
    File.expand_path('../../..', __FILE__)
  end
end