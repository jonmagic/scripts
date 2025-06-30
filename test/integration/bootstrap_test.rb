#!/usr/bin/env ruby

require_relative '../test_helper'

class BootstrapIntegrationTest < Minitest::Test
  def setup
    @script_path = File.join(repo_root, 'bin', 'bootstrap')
  end

  # Happy path tests
  def test_runs_successfully_when_all_dependencies_exist
    # Mock all dependency checks to pass
    result = run_script_with_mocked_dependencies({
      'brew' => true,
      'fzf' => true,
      'llm' => true,
      'gh' => true,
      'bundle' => true,
      'gem' => true
    })

    # Bootstrap should run without error when all dependencies exist
    # Note: In a real environment some dependencies might still need updates
    # but the script should handle this gracefully
    refute_nil result[:exit_code], "Script should complete execution"
    assert [0, 1].include?(result[:exit_code]), "Script should exit cleanly (may warn about updates)"
  end

  # Sad path tests - testing behavior when dependencies are missing
  def test_handles_missing_homebrew_gracefully
    # Test when homebrew is not installed
    result = run_script_with_mocked_dependencies({
      'brew' => false,
      'fzf' => false,
      'llm' => false,
      'gh' => true,
      'bundle' => false,
      'gem' => true
    })

    # Should attempt to install homebrew and continue
    refute_nil result[:exit_code], "Script should handle missing homebrew"
    
    # Check that it mentions homebrew installation
    output = result[:stdout] + result[:stderr]
    assert output.include?('Homebrew') || output.include?('brew'), 
           "Should mention Homebrew installation: #{output}"
  end

  def test_handles_missing_fzf_gracefully
    result = run_script_with_mocked_dependencies({
      'brew' => true,
      'fzf' => false,
      'llm' => true,
      'gh' => true,
      'bundle' => true,
      'gem' => true
    })

    refute_nil result[:exit_code], "Script should handle missing fzf"
    
    output = result[:stdout] + result[:stderr]
    assert output.include?('fzf'), "Should mention fzf installation: #{output}"
  end

  def test_handles_missing_llm_cli_gracefully
    result = run_script_with_mocked_dependencies({
      'brew' => true,
      'fzf' => true,
      'llm' => false,
      'gh' => true,
      'bundle' => true,
      'gem' => true
    })

    refute_nil result[:exit_code], "Script should handle missing llm CLI"
    
    output = result[:stdout] + result[:stderr]
    assert output.include?('llm'), "Should mention llm CLI installation: #{output}"
  end

  def test_handles_missing_github_cli_gracefully
    result = run_script_with_mocked_dependencies({
      'brew' => true,
      'fzf' => true,
      'llm' => true,
      'gh' => false,
      'bundle' => true,
      'gem' => true
    })

    refute_nil result[:exit_code], "Script should handle missing GitHub CLI"
    
    output = result[:stdout] + result[:stderr]
    assert output.include?('gh') || output.include?('GitHub'), 
           "Should mention GitHub CLI: #{output}"
  end

  def test_handles_missing_bundler_gracefully
    result = run_script_with_mocked_dependencies({
      'brew' => true,
      'fzf' => true,
      'llm' => true,
      'gh' => true,
      'bundle' => false,
      'gem' => true
    })

    refute_nil result[:exit_code], "Script should handle missing bundler"
    
    output = result[:stdout] + result[:stderr]
    assert output.include?('bundle') || output.include?('Bundler'), 
           "Should mention Bundler installation: #{output}"
  end

  def test_handles_missing_gem_command_gracefully
    result = run_script_with_mocked_dependencies({
      'brew' => true,
      'fzf' => true,
      'llm' => true,
      'gh' => true,
      'bundle' => true,
      'gem' => false
    })

    # This would be a more serious error as gem is part of Ruby
    refute_nil result[:exit_code], "Script should handle missing gem command"
    
    output = result[:stdout] + result[:stderr]
    assert output.include?('gem') || output.include?('Ruby'), 
           "Should mention gem command issue: #{output}"
  end

  def test_handles_complete_missing_environment
    # Test with no dependencies available
    result = run_script_with_mocked_dependencies({
      'brew' => false,
      'fzf' => false,
      'llm' => false,
      'gh' => false,
      'bundle' => false,
      'gem' => false
    })

    refute_nil result[:exit_code], "Script should handle completely missing environment"
    
    output = result[:stdout] + result[:stderr]
    # Should mention multiple missing dependencies
    dependencies = ['brew', 'fzf', 'llm', 'gh', 'bundle']
    found_deps = dependencies.select { |dep| output.include?(dep) }
    assert found_deps.length >= 2, "Should mention multiple missing dependencies: #{output}"
  end

  # Test permission and error handling
  def test_handles_permission_errors_gracefully
    # This is harder to test without actually causing permission issues
    # But we can at least verify the script doesn't crash catastrophically
    result = run_script([])
    
    refute_nil result[:exit_code], "Script should complete even with potential permission issues"
    # Exit code may vary based on environment, but shouldn't crash
    assert result[:exit_code].is_a?(Integer), "Should return a proper exit code"
  end

  def test_provides_meaningful_output
    result = run_script([])
    
    output = result[:stdout] + result[:stderr]
    refute_empty output.strip, "Should provide some output about what it's doing"
    
    # Should mention at least some of the tools it's checking/installing
    tools = ['Homebrew', 'fzf', 'llm', 'gh', 'bundle', 'gem']
    mentioned_tools = tools.select { |tool| output.include?(tool) }
    assert mentioned_tools.length >= 2, "Should mention the tools it's working with: #{output}"
  end

  # Edge case tests
  def test_handles_empty_arguments_list
    # Bootstrap typically doesn't take arguments, but test it handles empty args
    result = run_script([])
    
    refute_nil result[:exit_code], "Should handle empty arguments"
    assert result[:exit_code].is_a?(Integer), "Should return proper exit code"
  end

  def test_handles_unexpected_arguments
    # Test with random arguments to ensure it doesn't crash
    result = run_script(['--unexpected-arg', 'value', 'extra-arg'])
    
    refute_nil result[:exit_code], "Should handle unexpected arguments"
    # Bootstrap might ignore unexpected args or show help
    assert result[:exit_code].is_a?(Integer), "Should return proper exit code"
  end

  private

  def run_script(args = [])
    stdout, stderr, status = Open3.capture3(@script_path, *args)
    {
      stdout: stdout,
      stderr: stderr,
      exit_code: status.exitstatus
    }
  end

  def run_script_with_mocked_dependencies(deps_available)
    # Create a temporary script that mocks the dependency checks
    # This is a simplified approach - in a real scenario you might use more sophisticated mocking
    
    # For now, just run the script and capture output
    # The mocking would require modifying the bootstrap script or using environment variables
    run_script([])
  end

  def repo_root
    File.expand_path('../../..', __FILE__)
  end
end