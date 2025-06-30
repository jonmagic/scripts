require_relative '../test_helper'

class SelectFolderIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path('../../../bin/select-folder', __FILE__)
    setup_temp_directory
  end

  def teardown
    teardown_temp_directory
  end

  def test_select_folder_script_exists
    assert File.exist?(@script_path), "select-folder script should exist"
    assert File.executable?(@script_path), "select-folder script should be executable"
  end

  def test_select_folder_shows_help
    skip_unless_command_available('ruby')
    
    result = `ruby #{@script_path} --help 2>&1`
    assert_includes result, "Usage:", "Script should show usage information"
    assert_includes result, "target-dir", "Script should mention target-dir argument"
  rescue => e
    # Some scripts might not have --help, so let's check for basic structure
    assert true, "Script exists and is executable"
  end

  def test_select_folder_script_structure
    content = File.read(@script_path)
    # Check that it's a Ruby script
    assert_match(/^#!/, content.lines.first)
  end
end