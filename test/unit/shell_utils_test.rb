require_relative '../test_helper'
require 'shell_utils'

class ShellUtilsTest < Minitest::Test
  include ShellUtils

  def test_execute_command_with_successful_command
    result = execute_command("echo 'hello world'")

    assert result[:success]
    assert_equal 0, result[:exit_code]
    assert_includes result[:stdout], "hello world"
    assert_equal "", result[:stderr]
  end

  def test_execute_command_with_failing_command
    result = execute_command("nonexistentcommand123456")

    refute result[:success]
    refute_equal 0, result[:exit_code]
    refute_empty result[:stderr]
  end

  def test_execute_command_with_stdin_data
    result = execute_command("cat", stdin_data: "test input")

    assert result[:success]
    assert_equal "test input", result[:stdout]
  end

  def test_execute_command_bang_with_successful_command
    output = execute_command!("echo 'success'")
    assert_includes output, "success"
  end

  def test_execute_command_bang_raises_on_failure
    assert_raises(RuntimeError, Errno::ENOENT) do
      execute_command!("nonexistentcommand123456")
    end
  end

  def test_command_exists_with_existing_command
    assert command_exists?("echo")
  end

  def test_command_exists_with_nonexistent_command
    refute command_exists?("nonexistentcommand123456")
  end
end
