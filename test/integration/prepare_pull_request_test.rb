require_relative '../test_helper'

class PreparePullRequestIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path('../../../bin/prepare-pull-request', __FILE__)
    setup_temp_directory
    @prompt_file = fixture_path('pr_prompt.txt')
  end

  def teardown
    teardown_temp_directory
  end

  def test_script_exists_and_executable
    assert File.exist?(@script_path), "prepare-pull-request script should exist"
    assert File.executable?(@script_path), "prepare-pull-request script should be executable"
  end

  def test_shows_help_message
    result = run_script('prepare-pull-request', ['--help'])
    
    assert result[:success], "Help command should succeed"
    assert_includes result[:stdout], "Usage:", "Should show usage information"
    assert_includes result[:stdout], "base-branch", "Should mention base-branch argument"
    assert_includes result[:stdout], "pr-body-prompt-path", "Should mention pr-body-prompt-path argument"
  end

  def test_requires_base_branch_argument
    result = run_script('prepare-pull-request', ['--pr-body-prompt-path', @prompt_file])
    
    refute result[:success], "Should fail without base branch"
    assert_includes result[:combined], "Error:", "Should show error message"
    assert_includes result[:combined], "base branch", "Should mention missing base branch"
  end

  def test_requires_prompt_path_argument
    result = run_script('prepare-pull-request', ['--base-branch', 'main'])
    
    refute result[:success], "Should fail without prompt path"
    assert_includes result[:combined], "Error:", "Should show error message"
    assert_includes result[:combined], "PR body prompt template", "Should mention missing prompt path"
  end

  def test_validates_prompt_path_exists
    nonexistent_path = File.join(@temp_dir, 'nonexistent.txt')
    result = run_script('prepare-pull-request', [
      '--base-branch', 'main', 
      '--pr-body-prompt-path', nonexistent_path
    ])
    
    refute result[:success], "Should fail with nonexistent prompt file"
    assert_includes result[:combined], "Error:", "Should show error message"
    assert_includes result[:combined], "valid path", "Should mention invalid path"
  end

  def test_full_workflow_with_main_base_branch
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_workflow_with_custom_llm_model
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_edit_title_workflow
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_edit_body_workflow
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_decline_to_create_pr
    skip "Complex workflow tests require better mocking infrastructure"
  end

  def test_handles_invalid_base_branch
    git_repo = setup_test_git_repo_with_feature_branch
    
    Dir.chdir(git_repo) do
      system("git checkout feature-branch")
      
      result = run_script('prepare-pull-request', [
        '--base-branch', 'nonexistent-branch',
        '--pr-body-prompt-path', @prompt_file
      ])
      
      refute result[:success], "Should fail with invalid base branch"
      assert_includes result[:combined], "Error:", "Should show error message"
    end
  end

  def test_validates_git_repository
    # Run in non-git directory
    Dir.chdir(@temp_dir) do
      result = run_script('prepare-pull-request', [
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_file
      ])
      
      refute result[:success], "Should fail outside git repository"
    end
  end

  def test_handles_no_commits_between_branches
    git_repo = setup_test_git_repo
    
    Dir.chdir(git_repo) do
      # Create a branch but don't add any commits
      system("git checkout -b empty-branch")
      
      result = run_script('prepare-pull-request', [
        '--base-branch', 'main',
        '--pr-body-prompt-path', @prompt_file
      ])
      
      refute result[:success], "Should fail with no commits between branches"
      assert_includes result[:combined], "are you on a branch with commits", "Should mention no commits"
    end
  end

  private

  def setup_test_git_repo_with_feature_branch
    git_repo = setup_test_git_repo
    
    Dir.chdir(git_repo) do
      # Create and switch to main branch
      system("git checkout -b main")
      
      # Create a feature branch with some commits
      system("git checkout -b feature-branch")
      
      # Add some commits to feature branch
      File.write("feature.rb", "class Feature\n  def initialize\n    @name = 'test'\n  end\nend\n")
      system("git add feature.rb")
      system("git commit --quiet -m 'feat: add feature class'")
      
      File.write("test.rb", "require 'minitest/autorun'\n\nclass FeatureTest < Minitest::Test\n  def test_feature\n    assert true\n  end\nend\n")
      system("git add test.rb")
      system("git commit --quiet -m 'test: add feature tests'")
    end
    
    git_repo
  end

  def mock_git_operations(git_repo)
    # Mock git operations needed for PR workflow
    create_mock_command('git', %{
      case "$1" in
        "rev-parse")
          if [[ "$*" == *"@{u}"* ]]; then
            echo "origin/feature-branch"
            exit 0
          else
            exec /usr/bin/git "$@"
          fi
          ;;
        "push")
          echo "Branch pushed successfully"
          exit 0
          ;;
        *)
          exec /usr/bin/git "$@"
          ;;
      esac
    })
  end
end
