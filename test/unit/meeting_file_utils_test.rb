require_relative '../test_helper'
require 'meeting_file_utils'

class MeetingFileUtilsTest < Minitest::Test
  def setup
    setup_temp_directory
  end

  def teardown
    teardown_temp_directory
  end

  def test_ensure_subfolders_creates_directories
    MeetingFileUtils.ensure_subfolders(target_dir: @temp_dir)
    
    %w[Executive\ Summaries Meeting\ Notes Transcripts Weekly\ Notes].each do |subdir|
      path = File.join(@temp_dir, subdir)
      assert Dir.exist?(path), "Should create #{subdir} directory"
    end
  end

  def test_find_transcript_files_finds_txt_and_vtt
    # Create test files
    File.write(File.join(@temp_dir, "transcript1.txt"), "content")
    File.write(File.join(@temp_dir, "transcript2.vtt"), "content")
    File.write(File.join(@temp_dir, "other.log"), "content")
    
    files = MeetingFileUtils.find_transcript_files(folder: @temp_dir)
    
    assert_equal 2, files.length
    assert files.any? { |f| f.end_with?("transcript1.txt") }
    assert files.any? { |f| f.end_with?("transcript2.vtt") }
    refute files.any? { |f| f.end_with?("other.log") }
  end

  def test_prepare_transcript_dir_creates_and_returns_path
    date = "2024-01-15"
    result = MeetingFileUtils.prepare_transcript_dir(transcripts_base: @temp_dir, meeting_date: date)
    
    expected_path = File.join(@temp_dir, date)
    assert_equal expected_path, result
    assert Dir.exist?(result)
  end

  def test_next_transcript_filename_returns_01_for_empty_dir
    result = MeetingFileUtils.next_transcript_filename(dest_dir: @temp_dir)
    assert_equal "01.md", result
  end

  def test_next_transcript_filename_increments_when_files_exist
    File.write(File.join(@temp_dir, "01.md"), "content")
    File.write(File.join(@temp_dir, "02.md"), "content")
    
    result = MeetingFileUtils.next_transcript_filename(dest_dir: @temp_dir)
    assert_equal "03.md", result
  end

  def test_update_meeting_notes_file_creates_new_file
    notes_file = File.join(@temp_dir, "test_notes.md")
    
    MeetingFileUtils.update_meeting_notes_file_with_details(
      meeting_notes_file: notes_file,
      meeting_date: "2024-01-15",
      transcript_link: "[[transcript_link]]",
      summary_link: "[[summary_link]]",
      detailed_notes: "- Point 1\n- Point 2",
      filename: "01"
    )
    
    assert File.exist?(notes_file)
    content = File.read(notes_file)
    assert_includes content, "# Meeting Notes"
    assert_includes content, "## 2024-01-15"
    assert_includes content, "[[transcript_link]]"
    assert_includes content, "[[summary_link]]"
    assert_includes content, "- Point 1"
    assert_includes content, "- Point 2"
  end
end