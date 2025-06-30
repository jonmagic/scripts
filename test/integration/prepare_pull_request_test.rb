require_relative '../test_helper'

class PrepareFullRequestIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path('../../../bin/prepare-pull-request', __FILE__)
    setup_temp_directory
  end

  def teardown
    teardown_temp_directory
  end

  def test_prepare_pull_request_script_exists
    assert File.exist?(@script_path), "prepare-pull-request script should exist"
    assert File.executable?(@script_path), "prepare-pull-request script should be executable"
  end

  def test_prepare_pull_request_shows_help
    skip_unless_command_available('ruby')
    
    result = `ruby #{@script_path} --help 2>&1`
    assert_includes result, "Usage:", "Script should show usage information"
    assert_includes result, "base-branch", "Script should mention base-branch argument"
    assert_includes result, "pr-body-prompt-path", "Script should mention pr-body-prompt-path argument"
  end

  def test_prepare_pull_request_requires_arguments
    skip_unless_command_available('ruby')
    
    result = `ruby #{@script_path} 2>&1`
    assert_includes result, "Error:", "Script should show error without required args"
    refute_equal 0, $?.exitstatus, "Script should exit with non-zero status"
  end

  def test_prepare_pull_request_script_structure
    content = File.read(@script_path)
    assert_includes content, "OptionParser", "Script should use OptionParser"
    assert_includes content, "error_exit", "Script should use error_exit function"
    assert_includes content, "check_dependency", "Script should check dependencies"
  end

  def test_prepare_pull_request_checks_dependencies
    content = File.read(@script_path)
    %w[git gh llm].each do |dep|
      assert_includes content, dep, "Script should check for #{dep} dependency"
    end
  end
end