require_relative '../test_helper'

class ArchiveMeetingIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path('../../../bin/archive-meeting', __FILE__)
    setup_temp_directory
  end

  def teardown
    teardown_temp_directory
  end

  def test_archive_meeting_script_exists
    assert File.exist?(@script_path), "archive-meeting script should exist"
    assert File.executable?(@script_path), "archive-meeting script should be executable"
  end

  def test_archive_meeting_shows_help
    skip_unless_command_available('ruby')

    result = `ruby #{@script_path} --help 2>&1`
    assert_includes result, "Usage:", "Script should show usage information"
    assert_includes result, "transcripts-dir", "Script should mention transcripts-dir argument"
    assert_includes result, "target-dir", "Script should mention target-dir argument"
  end

  def test_archive_meeting_requires_arguments
    skip_unless_command_available('ruby')

    result = `ruby #{@script_path} 2>&1`
    refute_equal 0, $?.exitstatus, "Script should exit with non-zero status without args"
  end

  def test_archive_meeting_script_structure
    content = File.read(@script_path)
    assert_includes content, "OptionParser", "Script should use OptionParser"
    assert_includes content, "MeetingFileUtils", "Script should use MeetingFileUtils module"
    assert_includes content, "LlmUtils", "Script should use LlmUtils module"
  end

  def test_archive_meeting_has_required_modules
    content = File.read(@script_path)
    %w[MeetingFileUtils LlmUtils].each do |mod|
      assert_includes content, mod, "Script should reference #{mod} module"
    end
  end
end
