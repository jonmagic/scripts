require_relative '../test_helper'

class SelectFolderIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path('../../../bin/select-folder', __FILE__)
    setup_temp_directory
  end

  def teardown
    teardown_temp_directory
  end

  def test_script_exists_and_executable
    assert File.exist?(@script_path), "select-folder script should exist"
    assert File.executable?(@script_path), "select-folder script should be executable"
  end

  def test_shows_usage_without_arguments
    result = run_script('select-folder')
    
    refute result[:success], "Should fail without arguments"
    assert_includes result[:combined], "Usage:", "Should show usage information"
    assert_includes result[:combined], "target-dir", "Should mention target-dir argument"
  end

  def test_validates_target_directory_exists
    nonexistent_dir = File.join(@temp_dir, 'nonexistent')
    result = run_script('select-folder', ['--target-dir', nonexistent_dir])
    
    refute result[:success], "Should fail with nonexistent directory"
    assert_includes result[:combined], "Usage:", "Should show usage when directory doesn't exist"
  end

  def test_handles_directory_with_no_subfolders
    # Create empty directory
    empty_dir = File.join(@temp_dir, 'empty')
    Dir.mkdir(empty_dir)
    
    result = run_script('select-folder', ['--target-dir', empty_dir])
    
    refute result[:success], "Should fail when no subfolders exist"
    assert_includes result[:combined], "No subfolders found", "Should mention no subfolders"
  end

  def test_selects_folder_with_fzf
    # Create test directory structure
    test_dir = setup_test_directory_structure
    
    # Mock fzf to select the first folder
    selected_folder = File.join(test_dir, 'folder1')
    cleanup_fzf = mock_fzf_selection(selected_folder)
    
    result = run_script('select-folder', ['--target-dir', test_dir])
    
    assert result[:success], "Should succeed with valid directory and selection"
    assert_includes result[:stdout], selected_folder, "Should output selected folder"
    assert_includes result[:stdout], "/", "Should append trailing slash"
    
    cleanup_fzf.call
  end

  def test_handles_empty_fzf_selection
    test_dir = setup_test_directory_structure
    
    # Mock fzf to return empty selection (exit with status 1)
    cleanup_fzf = create_mock_command('fzf', 'exit 1')
    
    result = run_script('select-folder', ['--target-dir', test_dir])
    
    refute result[:success], "Should fail when fzf selection is cancelled"
    assert_empty result[:stdout].strip, "Should not output anything when cancelled"
    
    cleanup_fzf.call
  end

  def test_uses_current_directory_as_default
    # Create subfolders in temp directory
    Dir.mkdir(File.join(@temp_dir, 'subfolder1'))
    Dir.mkdir(File.join(@temp_dir, 'subfolder2'))
    
    # Mock fzf to select the first folder
    selected_folder = File.join(@temp_dir, 'subfolder1')
    cleanup_fzf = mock_fzf_selection(selected_folder)
    
    Dir.chdir(@temp_dir) do
      result = run_script('select-folder')  # No --target-dir specified
      
      assert result[:success], "Should use current directory as default"
      assert_includes result[:stdout], selected_folder, "Should select from current directory"
    end
    
    cleanup_fzf.call
  end

  private

  def setup_test_directory_structure
    test_dir = File.join(@temp_dir, 'test_dir')
    Dir.mkdir(test_dir)
    
    # Create some test folders
    %w[folder1 folder2 folder3].each do |folder|
      Dir.mkdir(File.join(test_dir, folder))
    end
    
    test_dir
  end
end
