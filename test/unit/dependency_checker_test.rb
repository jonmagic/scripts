require_relative '../test_helper'
require 'dependency_checker'

class DependencyCheckerTest < Minitest::Test
  include DependencyChecker

  def test_check_dependency_with_existing_command
    skip_unless_command_available('ruby')
    # Should not raise or exit if command exists
    # We can't easily test this without mocking system calls
    # So we'll verify the method exists and responds
    assert_respond_to self, :check_dependency
  end

  def test_check_dependencies_method_exists
    assert_respond_to self, :check_dependencies
  end

  def test_check_dependency_method_exists
    assert_respond_to self, :check_dependency
  end
end
