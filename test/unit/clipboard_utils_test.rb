require_relative '../test_helper'
require 'clipboard_utils'

class ClipboardUtilsTest < Minitest::Test
  include ClipboardUtils

  def test_clipboard_available_returns_boolean
    result = clipboard_available?
    assert [true, false].include?(result)
  end

  def test_copy_to_clipboard_method_exists
    assert_respond_to self, :copy_to_clipboard
  end

  def test_copy_to_clipboard_handles_missing_pbcopy
    # Test that it doesn't crash when pbcopy is not available
    # This is mostly for non-macOS systems
    # Just verify method responds correctly
    copy_to_clipboard("test content")
    # If we get here without exception, the method handled missing pbcopy gracefully
    assert true
  end

  def test_clipboard_available_method_exists
    assert_respond_to self, :clipboard_available?
  end
end