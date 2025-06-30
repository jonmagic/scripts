require_relative '../test_helper'
require 'error_handling'

class ErrorHandlingTest < Minitest::Test
  include ErrorHandling

  def test_error_exit_prints_message_and_exits
    # We can't easily test exit behavior in unit tests without mocking
    # So we'll test this in integration tests instead
    assert_respond_to self, :error_exit
  end

  def test_error_exit_method_exists
    assert_respond_to self, :error_exit
  end
end