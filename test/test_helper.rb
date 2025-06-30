#!/usr/bin/env ruby

require 'minitest/autorun'
require 'minitest/pride'
require 'tempfile'
require 'fileutils'
require 'open3'

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

  # Create a temporary file with content
  def create_temp_file(content, filename = nil)
    file = if filename
             Tempfile.new([filename, '.tmp'])
           else
             Tempfile.new('test')
           end
    file.write(content)
    file.flush
    file
  end

  # Assert that a command exists in PATH
  def assert_command_exists(command)
    assert system("which #{command} > /dev/null 2>&1"), "Command '#{command}' not found in PATH"
  end

  # Capture stdout and stderr from a block
  def capture_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new

    yield

    { stdout: $stdout.string, stderr: $stderr.string }
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  # Skip test if external dependency is not available
  def skip_unless_command_available(command)
    skip "#{command} not available" unless system("which #{command} > /dev/null 2>&1")
  end
end
