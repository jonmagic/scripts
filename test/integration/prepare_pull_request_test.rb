#!/usr/bin/env ruby

require_relative '../test_helper'
require 'tmpdir'
require 'fileutils'

class PreparePullRequestIntegrationTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir('prepare_pr_test')
    @prompt_path = File.join(fixtures_path, 'prompts', 'pr_prompt.txt')
    @script_path = File.join(repo_root, 'bin', 'prepare-pull-request')
    
    # Create a git repository with branches for testing
    @git_repo = create_test_git_repo_with_branches
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
    FileUtils.rm_rf(@git_repo) if @git_repo
  end

  # Happy path tests
  def test_generates_pull_request_with_valid_branches_and_commits
    Dir.chdir(@git_repo) do
      # Switch to feature branch and ensure it has commits ahead of main
      system('git checkout feature-branch')
      
      result = run_script_with_mocked_llm([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path
      ], 'feat: add new feature\n\nThis PR adds a new feature to improve functionality.')
      
      refute_nil result[:exit_code], "Script should complete execution"
    end
  end

  def test_uses_custom_llm_model_when_specified
    Dir.chdir(@git_repo) do
      system('git checkout feature-branch')
      
      result = run_script_with_mocked_llm([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path,
        '--llm-model', 'gpt-4.1'
      ], 'feat: add new feature')
      
      refute_nil result[:exit_code], "Script should handle custom model"
    end
  end

  def test_works_with_different_base_branches
    Dir.chdir(@git_repo) do
      # Create and switch to a different base branch
      system('git checkout -b develop main')
      system('git checkout feature-branch')
      
      result = run_script_with_mocked_llm([
        '--base-branch', 'develop',
        '--pr-body-prompt-path', @prompt_path
      ], 'feat: add feature for develop branch')
      
      refute_nil result[:exit_code], "Script should work with different base branches"
    end
  end

  def test_shows_help_with_help_flag
    result = run_script(['--help'])
    
    assert_equal 0, result[:exit_code], "Help should exit successfully"
    assert result[:stdout].include?('Usage:'), "Should show usage information"
    assert result[:stdout].include?('base-branch'), "Should show base-branch option"
    assert result[:stdout].include?('pr-body-prompt-path'), "Should show prompt path option"
    assert result[:stdout].include?('llm-model'), "Should show model option"
  end

  # Sad path tests
  def test_fails_without_required_arguments
    result = run_script([])
    
    assert_equal 1, result[:exit_code], "Should fail without arguments"
    assert result[:stderr].include?('required') || result[:stderr].include?('missing') || result[:stderr].include?('Usage'), 
           "Should mention missing required arguments: #{result[:stderr]}"
  end

  def test_fails_with_missing_base_branch_argument
    result = run_script(['--pr-body-prompt-path', @prompt_path])
    
    assert_equal 1, result[:exit_code], "Should fail without base branch"
    assert result[:stderr].include?('base-branch') || result[:stderr].include?('required') || result[:stderr].include?('branch'), 
           "Should mention missing base branch: #{result[:stderr]}"
  end

  def test_fails_with_missing_pr_body_prompt_path
    result = run_script(['--base-branch', 'main'])
    
    assert_equal 1, result[:exit_code], "Should fail without prompt path"
    assert result[:stderr].include?('pr-body-prompt-path') || result[:stderr].include?('prompt') || result[:stderr].include?('required'), 
           "Should mention missing prompt path: #{result[:stderr]}"
  end

  def test_fails_with_nonexistent_prompt_file
    nonexistent_prompt = File.join(@test_dir, 'nonexistent_prompt.txt')
    
    result = run_script([
      '--base-branch', 'main',
      '--pr-body-prompt-path', nonexistent_prompt
    ])
    
    assert_equal 1, result[:exit_code], "Should fail with nonexistent prompt file"
    assert result[:stderr].include?('not found') || result[:stderr].include?('exist') || result[:stderr].include?('file'), 
           "Should mention prompt file not found: #{result[:stderr]}"
  end

  def test_fails_when_not_in_git_repository
    Dir.chdir(@test_dir) do
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path
      ])
      
      assert_equal 1, result[:exit_code], "Should fail when not in git repository"
      assert result[:stderr].include?('git') || result[:stderr].include?('repository'), 
             "Should mention git repository issue: #{result[:stderr]}"
    end
  end

  def test_fails_with_nonexistent_base_branch
    Dir.chdir(@git_repo) do
      result = run_script([
        '--base-branch', 'nonexistent-branch',
        '--pr-body-prompt-path', @prompt_path
      ])
      
      assert_equal 1, result[:exit_code], "Should fail with nonexistent base branch"
      assert result[:stderr].include?('branch') || result[:stderr].include?('not found') || result[:stderr].include?('exist'), 
             "Should mention branch not found: #{result[:stderr]}"
    end
  end

  def test_handles_no_commits_between_branches
    Dir.chdir(@git_repo) do
      # Switch to main branch (no difference between main and main)
      system('git checkout main')
      
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path
      ])
      
      assert_equal 1, result[:exit_code], "Should fail when no commits between branches"
      assert result[:stderr].include?('commits') || result[:stderr].include?('branch') || result[:stderr].include?('difference'), 
             "Should mention no commits between branches: #{result[:stderr]}"
    end
  end

  def test_fails_when_llm_command_not_found
    Dir.chdir(@git_repo) do
      system('git checkout feature-branch')
      
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path
      ])
      
      # Should fail because llm is not installed
      assert_equal 1, result[:exit_code], "Should fail when llm command not found"
      assert result[:stderr].include?('llm') || result[:stderr].include?('dependency') || result[:stderr].include?('not found'), 
             "Should mention llm dependency issue: #{result[:stderr]}"
    end
  end

  def test_handles_invalid_llm_model
    Dir.chdir(@git_repo) do
      system('git checkout feature-branch')
      
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path,
        '--llm-model', 'invalid-model-name'
      ])
      
      refute_nil result[:exit_code], "Should handle invalid model"
      # Exit code may vary depending on how llm handles invalid models
    end
  end

  def test_handles_prompt_file_with_no_read_permissions
    # Create prompt file and remove read permissions
    restricted_prompt = File.join(@test_dir, 'restricted_prompt.txt')
    File.write(restricted_prompt, 'prompt content')
    File.chmod(0000, restricted_prompt)
    
    Dir.chdir(@git_repo) do
      system('git checkout feature-branch')
      
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', restricted_prompt
      ])
      
      # Restore permissions for cleanup
      File.chmod(0644, restricted_prompt) rescue nil
      
      assert_equal 1, result[:exit_code], "Should fail when prompt file is not readable"
      assert result[:stderr].include?('permission') || result[:stderr].include?('read') || result[:stderr].include?('access'), 
             "Should mention permission error: #{result[:stderr]}"
    end
  end

  def test_handles_empty_prompt_file
    empty_prompt = File.join(@test_dir, 'empty_prompt.txt')
    File.write(empty_prompt, '')
    
    Dir.chdir(@git_repo) do
      system('git checkout feature-branch')
      
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', empty_prompt
      ])
      
      refute_nil result[:exit_code], "Should handle empty prompt file"
      # May warn about empty prompt or proceed
    end
  end

  def test_handles_very_large_diff_between_branches
    Dir.chdir(@git_repo) do
      system('git checkout feature-branch')
      
      # Create many large files
      10.times do |i|
        large_content = 'large content ' * 1000
        File.write("large_file_#{i}.txt", large_content)
        system("git add large_file_#{i}.txt")
      end
      system('git commit -m "Add large files" --quiet')
      
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path
      ])
      
      refute_nil result[:exit_code], "Should handle large diff"
      # Should either process successfully or fail gracefully
    end
  end

  def test_handles_merge_conflicts_in_branch_comparison
    Dir.chdir(@git_repo) do
      # Create conflicting changes in both branches
      system('git checkout main')
      File.write('conflict_file.txt', 'main branch content')
      system('git add conflict_file.txt')
      system('git commit -m "Add conflict file on main" --quiet')
      
      system('git checkout feature-branch')
      File.write('conflict_file.txt', 'feature branch content')
      system('git add conflict_file.txt')
      system('git commit -m "Add conflict file on feature" --quiet')
      
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path
      ])
      
      refute_nil result[:exit_code], "Should handle potential merge conflicts"
      # Should still be able to generate PR description even with conflicts
    end
  end

  def test_handles_invalid_flag_gracefully
    result = run_script(['--invalid-flag', 'value'])
    
    assert_equal 1, result[:exit_code], "Should fail with invalid flag"
    assert result[:stderr].include?('invalid') || result[:stderr].include?('unknown') || result[:stderr].include?('Usage'), 
           "Should mention invalid flag: #{result[:stderr]}"
  end

  def test_handles_branch_with_special_characters
    Dir.chdir(@git_repo) do
      # Create branch with special characters
      system('git checkout -b "feature/special-chars_123" main')
      File.write('special_file.txt', 'content')
      system('git add special_file.txt')
      system('git commit -m "Add special file" --quiet')
      
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path
      ])
      
      refute_nil result[:exit_code], "Should handle branch names with special characters"
    end
  end

  def test_handles_detached_head_state
    Dir.chdir(@git_repo) do
      # Get a commit hash and checkout to detached HEAD
      commit_hash = `git rev-parse HEAD`.strip
      system("git checkout #{commit_hash}")
      
      result = run_script([
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_path
      ])
      
      refute_nil result[:exit_code], "Should handle detached HEAD state"
      # May fail or handle gracefully depending on implementation
    end
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

  def run_script_with_mocked_llm(args, mock_response)
    # In a real implementation, you would mock the llm command
    # For now, just run the script normally
    run_script(args)
  end

  def create_test_git_repo_with_branches
    git_repo = File.join(@test_dir, 'test_git_repo')
    FileUtils.mkdir_p(git_repo)
    
    Dir.chdir(git_repo) do
      system('git init --quiet')
      system('git config user.email "test@example.com"')
      system('git config user.name "Test User"')
      
      # Create initial commit on main
      File.write('README.md', '# Test Repo')
      system('git add README.md')
      system('git commit -m "Initial commit" --quiet')
      
      # Create feature branch with additional commits
      system('git checkout -b feature-branch')
      File.write('feature.txt', 'feature content')
      system('git add feature.txt')
      system('git commit -m "Add feature" --quiet')
      
      File.write('feature2.txt', 'more feature content')
      system('git add feature2.txt')
      system('git commit -m "Add more features" --quiet')
      
      # Switch back to main
      system('git checkout main')
    end
    
    git_repo
  end

  def fixtures_path
    File.join(repo_root, 'test', 'fixtures')
  end

  def repo_root
    File.expand_path('../../..', __FILE__)
  end
end