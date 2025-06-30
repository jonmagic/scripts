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

  # Skip test if external dependency is not available
  def skip_unless_command_available(command)
    skip "#{command} not available" unless system("which #{command} > /dev/null 2>&1")
  end
end
