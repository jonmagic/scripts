#!/usr/bin/env ruby

require 'minitest/autorun'
require 'minitest/pride'
require 'tempfile'
require 'fileutils'
require 'open3'
require 'json'

# Add lib directory to load path
$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

# Test helper methods
class Minitest::Test
  # Create a temporary directory for test files
  def setup_temp_directory
    @temp_dir = Dir.mktmpdir
  end

  # Clean up temporary directory
  def teardown_temp_directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  # Skip test if external dependency is not available
  def skip_unless_command_available(command)
    skip "#{command} not available" unless system("which #{command} > /dev/null 2>&1")
  end

  # Create a temporary git repository with some test files and changes
  def setup_test_git_repo(dir = @temp_dir)
    Dir.chdir(dir) do
      system("git init --quiet")
      system("git config user.name 'Test User'")
      system("git config user.email 'test@example.com'")
      
      # Create initial commit
      File.write("README.md", "# Test Repository\n")
      system("git add README.md")
      system("git commit --quiet -m 'Initial commit'")
    end
    dir
  end

  # Add staged changes to test git repo
  def add_staged_changes(dir, files = {"test.txt" => "Hello World\n"})
    Dir.chdir(dir) do
      files.each do |filename, content|
        File.write(filename, content)
        system("git add #{filename}")
      end
    end
  end

  # Create a fixture file path
  def fixture_path(filename)
    File.expand_path("../fixtures/#{filename}", __FILE__)
  end

  # Run a script with given arguments and optional stdin input
  def run_script(script_name, args = [], stdin_input = nil)
    script_path = File.expand_path("../../bin/#{script_name}", __FILE__)
    cmd = ["ruby", script_path] + args
    
    if stdin_input
      stdout, stderr, status = Open3.capture3(*cmd, stdin_data: stdin_input)
    else
      stdout, stderr, status = Open3.capture3(*cmd)
    end
    
    # Combine stdout and stderr for error checking since some scripts may print errors to stdout
    combined_output = "#{stdout}#{stderr}".strip
    
    {
      stdout: stdout,
      stderr: stderr,
      combined: combined_output,
      status: status,
      success: status.success?
    }
  end

  # Mock external command by creating a temporary script
  def create_mock_command(command_name, response_script)
    mock_dir = File.join(@temp_dir, "mock_bin")
    FileUtils.mkdir_p(mock_dir)
    
    mock_script = File.join(mock_dir, command_name)
    File.write(mock_script, "#!/bin/bash\n#{response_script}\n")
    File.chmod(0755, mock_script)
    
    # Add to PATH
    original_path = ENV['PATH']
    ENV['PATH'] = "#{mock_dir}:#{ENV['PATH']}"
    
    # Return cleanup proc
    proc { ENV['PATH'] = original_path }
  end

  # Mock fzf command to return a specific selection
  def mock_fzf_selection(selection)
    create_mock_command('fzf', "echo '#{selection}'")
  end

  # Mock llm command to return a specific response
  def mock_llm_response(response)
    create_mock_command('llm', "echo '#{response}'")
  end

  # Mock git command for specific operations
  def mock_git_command(operation, response)
    case operation
    when :diff_staged
      create_mock_command('git', %{
        if [[ "$1" == "diff" && "$2" == "--staged" ]]; then
          echo '#{response}'
        else
          exec /usr/bin/git "$@"
        fi
      })
    when :commit
      create_mock_command('git', %{
        if [[ "$1" == "commit" ]]; then
          echo "Commit successful"
          exit 0
        else
          exec /usr/bin/git "$@"
        fi
      })
    end
  end
end
