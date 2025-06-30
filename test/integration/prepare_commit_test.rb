require_relative '../test_helper'

class PrepareCommitIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path('../../../bin/prepare-commit', __FILE__)
    setup_temp_directory
    @prompt_file = fixture_path('commit_prompt.txt')
  end

  def teardown
    teardown_temp_directory
  end

  def test_script_exists_and_executable
    assert File.exist?(@script_path), "prepare-commit script should exist"
    assert File.executable?(@script_path), "prepare-commit script should be executable"
  end

  def test_shows_help_message
    result = run_script('prepare-commit', ['--help'])
    
    assert result[:success], "Help command should succeed"
    assert_includes result[:stdout], "Usage:", "Should show usage information"
    assert_includes result[:stdout], "commit-message-prompt-path", "Should mention required argument"
  end

  def test_requires_prompt_path_argument
    result = run_script('prepare-commit')
    
    refute result[:success], "Should fail without required arguments"
    assert_includes result[:combined], "Error:", "Should show error message"
    assert_includes result[:combined], "commit message prompt template", "Should mention missing prompt path"
  end

  def test_validates_prompt_path_exists
    nonexistent_path = File.join(@temp_dir, 'nonexistent.txt')
    result = run_script('prepare-commit', ['--commit-message-prompt-path', nonexistent_path])
    
    refute result[:success], "Should fail with nonexistent prompt file"
    assert_includes result[:combined], "Error:", "Should show error message"
    assert_includes result[:combined], "valid path", "Should mention invalid path"
  end

  def test_requires_staged_changes
    # Setup git repo but don't stage any changes
    git_repo = setup_test_git_repo
    
    Dir.chdir(git_repo) do
      result = run_script('prepare-commit', ['--commit-message-prompt-path', @prompt_file])
      
      refute result[:success], "Should fail without staged changes"
      assert_includes result[:combined], "No staged changes", "Should mention missing staged changes"
    end
  end

  def test_full_workflow_with_feat_commit_type
    # This test is complex and requires proper mocking of all external dependencies
    # For now, let's focus on testing the script structure and basic validation
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_workflow_with_fix_commit_type_and_scope
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_workflow_with_custom_llm_model
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_regenerate_commit_message_workflow
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_handles_different_commit_types
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_handles_empty_fzf_selection
    # This test requires better mocking of fzf to handle empty selection
    skip "Complex fzf mocking requires better infrastructure"
  end

  def test_validates_git_repository
    # Run in non-git directory
    Dir.chdir(@temp_dir) do
      result = run_script('prepare-commit', 
                         ['--commit-message-prompt-path', @prompt_file])
      
      refute result[:success], "Should fail outside git repository"
    end
  end
end
