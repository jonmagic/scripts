require_relative '../test_helper'
require 'date'

class CreateWeeklyNoteIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path('../../../bin/create-weekly-note', __FILE__)
    setup_temp_directory
    @template_file = fixture_path('weekly_template.md')
  end

  def teardown
    teardown_temp_directory
  end

  def test_script_exists_and_executable
    assert File.exist?(@script_path), "create-weekly-note script should exist"
    assert File.executable?(@script_path), "create-weekly-note script should be executable"
  end

  def test_shows_help_message
    result = run_script('create-weekly-note', ['--help'])
    
    assert result[:success], "Help command should succeed"
    assert_includes result[:stdout], "Usage:", "Should show usage information"
    assert_includes result[:stdout], "template-path", "Should mention template-path argument"
    assert_includes result[:stdout], "target-dir", "Should mention target-dir argument"
  end

  def test_requires_template_path_argument
    result = run_script('create-weekly-note', ['--target-dir', @temp_dir])
    
    refute result[:success], "Should fail without template path"
    assert_includes result[:combined], "Error:", "Should show error message"
    assert_includes result[:combined], "required", "Should mention required arguments"
  end

  def test_requires_target_dir_argument
    result = run_script('create-weekly-note', ['--template-path', @template_file])
    
    refute result[:success], "Should fail without target directory"
    assert_includes result[:combined], "Error:", "Should show error message"
    assert_includes result[:combined], "required", "Should mention required arguments"
  end

  def test_validates_template_file_exists
    nonexistent_template = File.join(@temp_dir, 'nonexistent.md')
    result = run_script('create-weekly-note', [
      '--template-path', nonexistent_template,
      '--target-dir', @temp_dir
    ])
    
    refute result[:success], "Should fail with nonexistent template"
    assert_includes result[:combined], "Template file not found", "Should mention template not found"
  end

  def test_validates_target_directory_exists
    nonexistent_dir = File.join(@temp_dir, 'nonexistent')
    result = run_script('create-weekly-note', [
      '--template-path', @template_file,
      '--target-dir', nonexistent_dir
    ])
    
    refute result[:success], "Should fail with nonexistent directory"
    assert_includes result[:combined], "Target directory not found", "Should mention directory not found"
  end

  def test_creates_weekly_note_successfully
    result = run_script('create-weekly-note', [
      '--template-path', @template_file,
      '--target-dir', @temp_dir
    ])
    
    assert result[:success], "Should succeed with valid arguments"
    
    # Find the created file
    created_files = Dir.glob(File.join(@temp_dir, "Week of *.md"))
    assert_equal 1, created_files.length, "Should create exactly one weekly note file"
    
    created_file = created_files.first
    assert File.exist?(created_file), "Created file should exist"
    assert File.file?(created_file), "Created path should be a file"
    
    # Verify file content
    content = File.read(created_file)
    assert_includes content, "Week of", "Should include week date"
    refute_includes content, "{{date}}", "Should replace date placeholder"
    refute_includes content, "{{monday:YYYY-MM-DD}}", "Should replace day placeholders"
  end

  def test_replaces_all_template_placeholders
    result = run_script('create-weekly-note', [
      '--template-path', @template_file,
      '--target-dir', @temp_dir
    ])
    
    assert result[:success], "Should succeed with valid arguments"
    
    created_file = Dir.glob(File.join(@temp_dir, "Week of *.md")).first
    content = File.read(created_file)
    
    # Verify specific date format replacements
    today = Date.today
    week_start = today.saturday? ? today + 1 : today - today.wday
    
    expected_date = week_start.strftime("%Y-%m-%d")
    assert_includes content, expected_date, "Should include correct week start date"
    
    # Verify day-specific replacements
    %w[sunday monday tuesday wednesday thursday friday saturday].each_with_index do |day, i|
      day_date = (week_start + i).strftime("%Y-%m-%d")
      assert_includes content, day_date, "Should include date for #{day}"
    end
    
    # Verify all placeholders are replaced
    refute_match(/\{\{.*\}\}/, content, "Should replace all template placeholders")
  end

  def test_handles_capitalized_day_names
    # Create a custom template with capitalized day placeholders
    custom_template = File.join(@temp_dir, 'custom_template.md')
    File.write(custom_template, "# Week {{date}}\n## Monday: {{Monday:YYYY-MM-DD}}\n## Sunday: {{Sunday:YYYY-MM-DD}}")
    
    result = run_script('create-weekly-note', [
      '--template-path', custom_template,
      '--target-dir', @temp_dir
    ])
    
    assert result[:success], "Should succeed with capitalized day names"
    
    created_file = Dir.glob(File.join(@temp_dir, "Week of *.md")).first
    content = File.read(created_file)
    
    # Verify capitalized placeholders are replaced
    refute_includes content, "{{Monday:YYYY-MM-DD}}", "Should replace capitalized Monday"
    refute_includes content, "{{Sunday:YYYY-MM-DD}}", "Should replace capitalized Sunday"
  end

  def test_calculates_correct_week_start_for_different_days
    # This test verifies the week calculation logic
    # We can't easily test all days without mocking Date.today, but we can test the logic
    
    result = run_script('create-weekly-note', [
      '--template-path', @template_file,
      '--target-dir', @temp_dir
    ])
    
    assert result[:success], "Should succeed with date calculation"
    
    created_file = Dir.glob(File.join(@temp_dir, "Week of *.md")).first
    filename = File.basename(created_file)
    
    # Extract date from filename and verify it's a Sunday (week start)
    date_match = filename.match(/Week of (\d{4}-\d{2}-\d{2})\.md/)
    assert date_match, "Filename should contain a date"
    
    week_date = Date.parse(date_match[1])
    assert_equal 0, week_date.wday, "Week should start on Sunday (wday = 0)"
  end

  def test_prevents_overwriting_existing_file
    # Create the weekly note first
    result1 = run_script('create-weekly-note', [
      '--template-path', @template_file,
      '--target-dir', @temp_dir
    ])
    assert result1[:success], "First creation should succeed"
    
    # Try to create again
    result2 = run_script('create-weekly-note', [
      '--template-path', @template_file,
      '--target-dir', @temp_dir
    ])
    
    refute result2[:success], "Should fail when file already exists"
    assert_includes result2[:combined], "File already exists", "Should mention file exists"
  end

  def test_uses_different_template_content
    # Create a custom template with different content
    custom_template = File.join(@temp_dir, 'custom.md')
    custom_content = "Custom weekly template for {{date}}\nMonday: {{monday:YYYY-MM-DD}}\nSpecial content here"
    File.write(custom_template, custom_content)
    
    result = run_script('create-weekly-note', [
      '--template-path', custom_template,
      '--target-dir', @temp_dir
    ])
    
    assert result[:success], "Should succeed with custom template"
    
    created_file = Dir.glob(File.join(@temp_dir, "Week of *.md")).first
    content = File.read(created_file)
    
    assert_includes content, "Custom weekly template", "Should use custom template content"
    assert_includes content, "Special content here", "Should preserve custom content"
    refute_includes content, "{{date}}", "Should still replace placeholders"
  end

  def test_handles_empty_template
    empty_template = File.join(@temp_dir, 'empty.md')
    File.write(empty_template, "")
    
    result = run_script('create-weekly-note', [
      '--template-path', empty_template,
      '--target-dir', @temp_dir
    ])
    
    assert result[:success], "Should succeed even with empty template"
    
    created_file = Dir.glob(File.join(@temp_dir, "Week of *.md")).first
    content = File.read(created_file)
    
    assert_equal "", content, "Empty template should create empty file"
  end

  def test_handles_template_with_no_placeholders
    plain_template = File.join(@temp_dir, 'plain.md')
    plain_content = "This is a plain template with no placeholders.\nJust static content."
    File.write(plain_template, plain_content)
    
    result = run_script('create-weekly-note', [
      '--template-path', plain_template,
      '--target-dir', @temp_dir
    ])
    
    assert result[:success], "Should succeed with plain template"
    
    created_file = Dir.glob(File.join(@temp_dir, "Week of *.md")).first
    content = File.read(created_file)
    
    assert_equal plain_content, content, "Plain template should be copied exactly"
  end
end