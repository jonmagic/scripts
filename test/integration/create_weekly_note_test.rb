#!/usr/bin/env ruby

require_relative '../test_helper'
require 'tmpdir'
require 'fileutils'
require 'date'

class CreateWeeklyNoteIntegrationTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir('create_weekly_note_test')
    @template_path = File.join(fixtures_path, 'templates', 'weekly_template.md')
    @simple_template_path = File.join(fixtures_path, 'templates', 'simple_template.md')
    @empty_template_path = File.join(fixtures_path, 'templates', 'empty_template.md')
    @script_path = File.join(repo_root, 'bin', 'create-weekly-note')
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  # Happy path tests
  def test_creates_weekly_note_with_valid_template
    result = run_script([
      '--template-path', @template_path,
      '--target-dir', @test_dir
    ])

    assert_equal 0, result[:exit_code], "Script should succeed: #{result[:stderr]}"
    
    # Check that file was created with correct date format
    expected_filename = Date.today.strftime('%Y-%m-%d') + '_weekly_notes.md'
    created_file = File.join(@test_dir, expected_filename)
    
    assert File.exist?(created_file), "Weekly note file should be created"
    
    # Check content has date substituted
    content = File.read(created_file)
    expected_date = Date.today.strftime('%Y-%m-%d')
    assert content.include?(expected_date), "Template should substitute date"
    refute content.include?('{{date}}'), "Template placeholder should be replaced"
    
    # Check structure is maintained
    assert content.include?('## Goals'), "Should maintain template structure"
    assert content.include?('## Meetings'), "Should maintain template structure"
  end

  def test_creates_weekly_note_with_simple_template
    result = run_script([
      '--template-path', @simple_template_path,
      '--target-dir', @test_dir
    ])

    assert_equal 0, result[:exit_code], "Script should succeed"
    
    expected_filename = Date.today.strftime('%Y-%m-%d') + '_weekly_notes.md'
    created_file = File.join(@test_dir, expected_filename)
    
    assert File.exist?(created_file), "Weekly note file should be created"
    
    content = File.read(created_file)
    expected_date = Date.today.strftime('%Y-%m-%d')
    assert content.include?(expected_date), "Should substitute date"
    refute content.include?('{{date}}'), "Should replace placeholder"
  end

  def test_creates_weekly_note_with_empty_template
    result = run_script([
      '--template-path', @empty_template_path,
      '--target-dir', @test_dir
    ])

    assert_equal 0, result[:exit_code], "Script should succeed even with empty template"
    
    expected_filename = Date.today.strftime('%Y-%m-%d') + '_weekly_notes.md'
    created_file = File.join(@test_dir, expected_filename)
    
    assert File.exist?(created_file), "Weekly note file should be created"
    
    content = File.read(created_file)
    assert_equal File.read(@empty_template_path), content, "Should copy empty template as-is"
  end

  def test_shows_help_with_help_flag
    result = run_script(['--help'])
    
    assert_equal 0, result[:exit_code], "Help should exit successfully"
    assert result[:stdout].include?('Usage:'), "Should show usage information"
    assert result[:stdout].include?('--template-path'), "Should show template path option"
    assert result[:stdout].include?('--target-dir'), "Should show target dir option"
  end

  # Sad path tests
  def test_fails_without_required_arguments
    result = run_script([])
    
    assert_equal 1, result[:exit_code], "Should fail without arguments"
    assert result[:stderr].include?('missing') || result[:stderr].include?('required'), 
           "Should mention missing/required arguments: #{result[:stderr]}"
  end

  def test_fails_with_missing_template_path_argument
    result = run_script(['--target-dir', @test_dir])
    
    assert_equal 1, result[:exit_code], "Should fail without template path"
    assert result[:stderr].include?('template') || result[:stderr].include?('missing'), 
           "Should mention missing template: #{result[:stderr]}"
  end

  def test_fails_with_missing_target_dir_argument
    result = run_script(['--template-path', @template_path])
    
    assert_equal 1, result[:exit_code], "Should fail without target dir"
    assert result[:stderr].include?('target') || result[:stderr].include?('missing'), 
           "Should mention missing target dir: #{result[:stderr]}"
  end

  def test_fails_with_nonexistent_template_file
    nonexistent_template = File.join(@test_dir, 'nonexistent.md')
    
    result = run_script([
      '--template-path', nonexistent_template,
      '--target-dir', @test_dir
    ])
    
    assert_equal 1, result[:exit_code], "Should fail with nonexistent template"
    assert result[:stderr].include?('not found') || result[:stderr].include?('exist'), 
           "Should mention file not found: #{result[:stderr]}"
  end

  def test_fails_with_nonexistent_target_directory
    nonexistent_dir = File.join(@test_dir, 'nonexistent_dir')
    
    result = run_script([
      '--template-path', @template_path,
      '--target-dir', nonexistent_dir
    ])
    
    assert_equal 1, result[:exit_code], "Should fail with nonexistent directory"
    assert result[:stderr].include?('not found') || result[:stderr].include?('exist'), 
           "Should mention directory not found: #{result[:stderr]}"
  end

  def test_fails_with_template_file_as_directory
    # Create a directory with the template name
    template_dir = File.join(@test_dir, 'template_dir')
    FileUtils.mkdir_p(template_dir)
    
    result = run_script([
      '--template-path', template_dir,
      '--target-dir', @test_dir
    ])
    
    assert_equal 1, result[:exit_code], "Should fail when template path is directory"
    assert result[:stderr].include?('not a file') || result[:stderr].include?('directory'), 
           "Should mention template is not a file: #{result[:stderr]}"
  end

  def test_prevents_overwriting_existing_file
    # Create existing weekly note
    expected_filename = Date.today.strftime('%Y-%m-%d') + '_weekly_notes.md'
    existing_file = File.join(@test_dir, expected_filename)
    File.write(existing_file, "Existing content")
    
    result = run_script([
      '--template-path', @template_path,
      '--target-dir', @test_dir
    ])
    
    assert_equal 1, result[:exit_code], "Should fail when file already exists"
    assert result[:stderr].include?('already exists') || result[:stderr].include?('overwrite'), 
           "Should mention file already exists: #{result[:stderr]}"
    
    # Verify original content is preserved
    assert_equal "Existing content", File.read(existing_file), "Should not overwrite existing file"
  end

  def test_handles_invalid_flag_gracefully
    result = run_script(['--invalid-flag', 'value'])
    
    assert_equal 1, result[:exit_code], "Should fail with invalid flag"
    assert result[:stderr].include?('invalid') || result[:stderr].include?('unknown'), 
           "Should mention invalid flag: #{result[:stderr]}"
  end

  def test_handles_template_with_read_permissions_denied
    # Create template file and remove read permissions
    restricted_template = File.join(@test_dir, 'restricted_template.md')
    File.write(restricted_template, "Template content")
    File.chmod(0000, restricted_template)
    
    result = run_script([
      '--template-path', restricted_template,
      '--target-dir', @test_dir
    ])
    
    # Restore permissions for cleanup
    File.chmod(0644, restricted_template) rescue nil
    
    assert_equal 1, result[:exit_code], "Should fail when template is not readable"
    assert result[:stderr].include?('permission') || result[:stderr].include?('read'), 
           "Should mention permission error: #{result[:stderr]}"
  end

  def test_handles_target_directory_with_write_permissions_denied
    # Create directory and remove write permissions
    restricted_dir = File.join(@test_dir, 'restricted_dir')
    FileUtils.mkdir_p(restricted_dir)
    File.chmod(0444, restricted_dir)
    
    result = run_script([
      '--template-path', @template_path,
      '--target-dir', restricted_dir
    ])
    
    # Restore permissions for cleanup
    File.chmod(0755, restricted_dir) rescue nil
    
    assert_equal 1, result[:exit_code], "Should fail when target directory is not writable"
    assert result[:stderr].include?('permission') || result[:stderr].include?('write'), 
           "Should mention permission error: #{result[:stderr]}"
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

  def fixtures_path
    File.join(repo_root, 'test', 'fixtures')
  end

  def repo_root
    File.expand_path('../../..', __FILE__)
  end
end